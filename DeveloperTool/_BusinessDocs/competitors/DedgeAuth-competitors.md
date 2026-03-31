# DedgeAuth — Competitor Analysis

**Product:** DedgeAuth — Centralized authentication service with JWT, magic-link email login, Windows SSO/AD integration, multi-tenant branding, per-app roles
**Category:** Self-Hosted Identity & Authentication Platform
**Date:** 2026-03-31

## Competitor Summary

| Name | URL | Pricing |
|------|-----|---------|
| Keycloak | https://www.keycloak.org | Free / Open Source |
| Authentik | https://goauthentik.io | Free / Open Source (Enterprise from $5/user/mo) |
| Ory (Kratos/Hydra) | https://www.ory.sh | Free / Open Source (Cloud from $29/mo) |
| ZITADEL | https://www.zitadel.com | Free tier → $100/mo+ |
| Kotauth | https://kotauth.com | Free / Open Source |
| Auth0 (Okta) | https://auth0.com | Free tier → $23/mo+ |

## Detailed Competitor Profiles

### Keycloak
Keycloak is the most established open-source identity and access management solution, backed by Red Hat. It supports OIDC, OAuth 2.0, SAML 2.0, MFA, SSO, social login, passkeys, LDAP/AD federation, and RBAC. The admin console provides full user and realm management. Managed hosting is available via Phase Two (from $0/free to $1,999/mo enterprise). **Key difference from DedgeAuth:** Keycloak is Java-based with significant operational complexity. DedgeAuth offers a simpler deployment with built-in magic-link login, Windows SSO/AD integration, and multi-tenant branding out of the box without the Java overhead.

### Authentik
Authentik is a modern open-source identity provider with a polished UI, supporting OAuth 2.0, SAML, LDAP, SCIM, proxy auth, and forward auth. It features flow-based authentication configuration, allowing custom login flows via a visual editor. Enterprise features include push MFA and audit logging. **Key difference:** Authentik uses a flow-based authentication model that's flexible but complex to configure. DedgeAuth provides opinionated defaults (JWT + magic-link + Windows SSO) that work immediately for enterprise Windows environments.

### Ory (Kratos/Hydra)
Ory provides modular open-source IAM tools: Kratos for user management, Hydra for OAuth 2.0/OIDC, Oathkeeper for access proxy, and Keto for authorization. The modular approach allows picking only needed components. Ory Cloud offers a managed option starting at $29/mo. **Key difference:** Ory is highly modular but requires assembling multiple services. DedgeAuth is a single unified service combining auth, JWT issuance, magic-link, AD integration, and multi-tenant branding.

### ZITADEL
ZITADEL is an API-first identity platform offering hosted login, modern authentication methods, SSO, social logins, RBAC, and extensibility through custom workflows. It supports multi-tenancy natively and offers both cloud and self-hosted options. **Key difference:** ZITADEL is cloud-first with self-hosting as secondary. DedgeAuth is self-hosted-first with Windows AD/SSO integration as a core feature rather than an add-on.

### Kotauth
Kotauth is a Docker-native self-hosted authentication platform with OAuth 2.0, OpenID Connect, multi-tenancy, flexible auth methods (passwords, TOTP, social OAuth), real-time webhooks, and per-tenant theming. Deployed with a single Docker command. **Key difference:** Kotauth is newer and less battle-tested. DedgeAuth includes Windows SSO/AD integration and magic-link email login as first-class features, while Kotauth focuses on standard OAuth flows.

### Auth0 (Okta)
Auth0 is the industry-standard managed authentication platform (acquired by Okta). It offers universal login, social connections, MFA, passwordless, machine-to-machine auth, and extensive SDKs. Free tier supports up to 25,000 MAU. Paid plans start at $23/mo. **Key difference:** Auth0 is cloud-only SaaS with per-user pricing that scales expensively. DedgeAuth is fully self-hosted with no per-user fees, native Windows AD/SSO, and no vendor dependency.
