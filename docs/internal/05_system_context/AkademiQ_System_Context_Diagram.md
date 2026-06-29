# AkademiQ System Context Diagram (C4 Level 1)

```mermaid
flowchart LR

subgraph Users
    SA[School Admin]
    TCH[Teacher]
    HM[Homeroom Teacher]
    STU[Student]
    PAR[Parent]
    SSA[SaaS Super Admin]
end

subgraph External Systems
    PG[Payment Gateway]
    MSG[Email / SMS / WhatsApp Provider]
    SSO[Optional SSO Provider]
end

System[AkademiQ SaaS Platform]

SA --> System
TCH --> System
HM --> System
STU --> System
PAR --> System
SSA --> System

System --> PG
System --> MSG
System --> SSO
```
