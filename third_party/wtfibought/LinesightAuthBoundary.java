package com.mawai.wiibsim.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Local signup and upstream development admin login stay closed in this deployment. */
@Component
public class LinesightAuthBoundary extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        String path = request.getRequestURI();
        if (path.startsWith("/api/auth/") && !path.equals("/api/auth/current")
                && !path.equals("/api/auth/logout") && !path.equals("/api/auth/linesight")) {
            response.setStatus(410);
            response.setContentType("application/json");
            response.getWriter().write("{\"code\":410,\"msg\":\"registration_closed\",\"data\":null}");
            return;
        }
        chain.doFilter(request, response);
    }
}
