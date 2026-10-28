package com.mawai.wiibsim.config;

import cn.dev33.satoken.stp.StpUtil;
import com.mawai.wiibcommon.entity.User;
import com.mawai.wiibcommon.util.Result;
import com.mawai.wiibsim.service.UserService;
import java.math.BigDecimal;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/** Deployment adapter: Keycloak/OAuth2 Proxy own login; Sa-Token owns WIIB sessions. */
@RestController
public class LinesightSsoController {
    private static final String ISSUER = "https://99ai.pronhubcn.com/sso/realms/linesight";
    private final UserService users;
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transactions;
    private final String adminSubject;
    private final NimbusJwtDecoder decoder;

    public LinesightSsoController(UserService users, JdbcTemplate jdbc,
            TransactionTemplate transactions,
            @Value("${LINESIGHT_WIIB_ADMIN_SUBJECT}") String adminSubject) {
        this.users = users;
        this.jdbc = jdbc;
        this.transactions = transactions;
        this.adminSubject = adminSubject;
        decoder = NimbusJwtDecoder.withJwkSetUri("http://127.0.0.1:8081/sso/realms/linesight/protocol/openid-connect/certs").build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(ISSUER),
                jwt -> "linesight-whatif".equals(jwt.getClaimAsString("azp"))
                        && jwt.getAudience().contains("wiib")
                        ? OAuth2TokenValidatorResult.success()
                        : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token"))));
    }

    @PostMapping("/api/auth/linesight")
    public Result<String> bootstrap(@RequestHeader(value="X-Forwarded-Access-Token", required=false) String token,
            @RequestHeader(value="satoken", required=false) String previous) {
        final Jwt jwt;
        try {
            if (token == null || token.isBlank()) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
            jwt = decoder.decode(token);
        } catch (JwtException failure) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        }
        String subject = jwt.getSubject();
        String username = jwt.getClaimAsString("preferred_username");
        if (subject == null || !subject.matches("[a-zA-Z0-9-]{1,48}")
                || username == null || !username.matches("[a-zA-Z0-9_.-]{2,64}")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        }
        String external = "linesight:" + subject;
        Long id = transactions.execute(status -> {
            jdbc.query("SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", rs -> {}, external);
            User user = users.findByLinuxDoId(external);
            if (user == null) {
                User collision = users.findByUsername(username);
                if (collision != null) throw new ResponseStatusException(HttpStatus.CONFLICT);
                user = new User();
                if (subject.equals(adminSubject)) user.setId(1L);
                user.setLinuxDoId(external);
                user.setUsername(username);
                user.setBalance(new BigDecimal("10000.00"));
                user.setLang("zh");
                users.save(user);
                users.recordInitialGrant(user.getId(), new BigDecimal("10000.00"));
            }
            return user.getId();
        });
        if (id == null || (id == 1L && !subject.equals(adminSubject))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        if (previous != null && id.toString().equals(String.valueOf(StpUtil.getLoginIdByToken(previous)))) {
            return Result.ok(previous);
        }
        StpUtil.login(id);
        return Result.ok(StpUtil.getTokenValue());
    }
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Result<Void>> authFailure(ResponseStatusException failure) {
        return ResponseEntity.status(failure.getStatusCode()).body(
                Result.fail(failure.getStatusCode().value(), "登录未完成，请重新登录"));
    }
}
