package com.linesight.identity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.authenticators.directgrant.AbstractDirectGrantAuthenticator;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.provider.ProviderConfigProperty;

/** Keycloak SPI: accept a short-lived, one-use server assertion after NFC device proof. */
public final class NfcTicketAuthenticator extends AbstractDirectGrantAuthenticator {
    public static final String ID = "linesight-nfc-ticket";

    @Override public void authenticate(AuthenticationFlowContext context) {
        try {
            if (!"linesight-nfc".equals(context.getAuthenticationSession().getClient().getClientId())) {
                throw new IllegalArgumentException();
            }
            String key = System.getenv("LINESIGHT_NFC_TICKET_SECRET");
            String ticket = context.getHttpRequest().getDecodedFormParameters().getFirst("nfc_ticket");
            if (key == null || key.length() < 43 || ticket == null || ticket.length() > 2048) {
                throw new IllegalArgumentException();
            }
            String[] parts = ticket.split("\\.", -1);
            if (parts.length != 2) throw new IllegalArgumentException();
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] expected = mac.doFinal(parts[0].getBytes(StandardCharsets.US_ASCII));
            if (!MessageDigest.isEqual(expected, Base64.getUrlDecoder().decode(parts[1]))) {
                throw new IllegalArgumentException();
            }
            String[] fields = new String(Base64.getUrlDecoder().decode(parts[0]), StandardCharsets.UTF_8).split("\\|", -1);
            if (fields.length != 5) throw new IllegalArgumentException();
            long now = Instant.now().getEpochSecond();
            long issued = Long.parseLong(fields[2]), expires = Long.parseLong(fields[3]);
            if (issued > now + 5 || issued < now - 35 || expires < now || expires > issued + 30
                    || !fields[1].matches("[0-9a-f-]{36}") || !fields[4].matches("[0-9a-f]{32}")) {
                throw new IllegalArgumentException();
            }
            UserModel user = context.getSession().users().getUserById(context.getRealm(), fields[0]);
            if (user == null || !user.isEnabled() || user.getServiceAccountClientLink() != null
                    || user.getRequiredActionsStream().findAny().isPresent()) {
                throw new IllegalArgumentException();
            }
            if (!context.getSession().singleUseObjects().putIfAbsent("linesight-nfc:" + fields[4], 60)) {
                throw new IllegalArgumentException();
            }
            context.setUser(user);
            context.getAuthenticationSession().setUserSessionNote("nfc_binding", fields[1]);
            context.getAuthenticationSession().setAuthNote("credential_type", "nfc-device");
            context.success();
        } catch (Exception failure) {
            context.failure(AuthenticationFlowError.INVALID_CREDENTIALS,
                    errorResponse(400, "invalid_grant", "Card authentication failed"));
        }
    }
    @Override public boolean requiresUser() { return false; }
    @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
    @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) { }
    @Override public boolean isUserSetupAllowed() { return false; }
    @Override public String getDisplayType() { return "LineSight NFC server assertion"; }
    @Override public String getReferenceCategory() { return "nfc-device"; }
    @Override public boolean isConfigurable() { return false; }
    @Override public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
        return new AuthenticationExecutionModel.Requirement[]{AuthenticationExecutionModel.Requirement.REQUIRED};
    }
    @Override public String getHelpText() { return "Validates a one-use server assertion for a device-bound NFC credential."; }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return List.of(); }
    @Override public String getId() { return ID; }
}
