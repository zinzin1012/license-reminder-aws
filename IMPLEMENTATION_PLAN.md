# LicenseReminder AWS — Implementation Plan

## Overview

Full serverless rebuild of LicenseReminder on 100% AWS infrastructure.
No Supabase, no Resend, no Cloudflare, no PM2.

- **Domain**: `license.dauhai1012.online`
- **Region**: `ap-southeast-1` (Singapore)
- **Repo**: `zinzin1012/license-reminder-aws`
- **Budget**: ~$2/month (within $99.50 trial, 179 days)

---

## Architecture

```
Route53 (dauhai1012.online)
├── license.dauhai1012.online → CloudFront
│   ├── /* → S3 (React + Vite SPA)
│   └── /api/* → API Gateway HTTP API → Lambda
│
├── Amazon Cognito (auth)
├── RDS PostgreSQL 16 (database)
├── S3 (file attachments)
├── SES (email)
├── EventBridge (cron)
├── SSM Parameter Store (secrets)
├── CloudWatch (logs)
└── Telegram Bot API (outbound HTTPS)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React 19 + Vite + TypeScript + React Router |
| State | Zustand (lightweight) |
| Auth | Amazon Cognito + `@aws-amplify/auth` |
| Backend | AWS Lambda (Node.js 20, ARM64) |
| API | API Gateway HTTP API |
| Database | RDS PostgreSQL 16 (t4g.micro) |
| Email | Amazon SES |
| Storage | S3 + presigned URLs |
| PDF | `@react-pdf/renderer` (in Lambda) |
| Validation | Zod |
| IaC | AWS SAM |
| CI/CD | GitHub Actions |
| Logging | CloudWatch (JSON structured) |

---

## Project Structure

```
license-reminder-aws/
├── frontend/                     # React + Vite SPA
│   ├── src/
│   │   ├── pages/               # Route-level components
│   │   ├── components/          # Shared UI components
│   │   ├── lib/                 # API client, auth, utils
│   │   ├── hooks/               # Custom React hooks
│   │   ├── stores/              # Zustand stores
│   │   ├── App.tsx              # React Router layout
│   │   ├── main.tsx             # Entry point
│   │   └── globals.css          # Design system (CSS variables)
│   ├── index.html
│   ├── vite.config.ts
│   ├── tsconfig.json
│   └── package.json
│
├── api/                          # Lambda functions
│   ├── functions/
│   │   ├── licenses/            # CRUD + bulk + import + renew
│   │   ├── reminders/           # trigger, send-now, digest, logs
│   │   ├── team/                # invite, members
│   │   ├── org/                 # settings, telegram
│   │   ├── reports/             # PDF generation
│   │   ├── audit/               # Activity log
│   │   ├── auth/                # accept-invite, setup-org
│   │   ├── attachments/         # Presigned URL generation
│   │   └── health.ts            # Health check
│   ├── lib/
│   │   ├── db.ts                # PostgreSQL connection pool
│   │   ├── auth.ts              # Cognito JWT verification
│   │   ├── email.ts             # SES client
│   │   ├── telegram.ts          # Telegram bot
│   │   ├── s3.ts                # S3 presigned URL helpers
│   │   ├── logger.ts            # Structured JSON logger
│   │   ├── response.ts          # Lambda response helpers
│   │   └── schemas/             # Zod validation schemas
│   ├── template.yaml            # SAM template
│   ├── tsconfig.json
│   └── package.json
│
├── shared/                       # Shared types between FE & API
│   ├── types.ts                 # Domain types
│   ├── constants.ts             # Shared constants
│   └── package.json
│
├── infra/                        # One-time infra setup scripts
│   ├── setup-rds.sh             # Create RDS instance
│   ├── setup-cognito.sh         # Create user pool
│   ├── setup-ses.sh             # Verify domain
│   ├── setup-s3.sh              # Create buckets
│   ├── setup-ssm.sh             # Store parameters
│   └── setup-cloudfront.sh      # Distribution + behaviors
│
├── migrations/                   # PostgreSQL migrations
│   ├── 001_initial_schema.sql
│   ├── 002_profiles.sql
│   ├── ...
│   └── 017_renewal_history.sql
│
├── .github/
│   └── workflows/
│       ├── deploy-api.yml       # Build + SAM deploy
│       └── deploy-frontend.yml  # Build + S3 sync + CF invalidation
│
├── IMPLEMENTATION_PLAN.md
├── deploy.sh                    # Manual deploy script
└── README.md
```

---

## Phases & Tasks

### Phase 1: AWS Infrastructure Setup (Week 1)

#### 1.1 RDS PostgreSQL
- [ ] Create VPC with public subnet (for trial simplicity)
- [ ] Create RDS PostgreSQL 16 instance (db.t4g.micro, free tier)
- [ ] Create database `licensereminder`
- [ ] Create app user: `lr_app` with limited privileges
- [ ] Store connection string in SSM: `/licensereminder/DATABASE_URL`
- [ ] Run existing migrations (001–017, adapted for plain PostgreSQL)

#### 1.2 Cognito User Pool
- [ ] Create User Pool: `licensereminder-users`
- [ ] Configure: email sign-in, password policy, email verification
- [ ] Create App Client: `licensereminder-web` (SRP + password auth)
- [ ] Store Pool ID and Client ID in SSM
- [ ] Test sign-up / sign-in / token flow

#### 1.3 SES Email
- [ ] Verify domain `dauhai1012.online` in SES (DKIM + SPF in Route53)
- [ ] Request production access (or test in sandbox)
- [ ] Test sending from `noreply@dauhai1012.online`

#### 1.4 S3 Buckets
- [ ] Create `licensereminder-frontend-dauhai` (static hosting)
- [ ] Create `licensereminder-attachments-dauhai` (private, CORS)
- [ ] Configure bucket policies

#### 1.5 CloudFront
- [ ] Create distribution for `license.dauhai1012.online`
- [ ] Origin 1: S3 bucket (default behavior)
- [ ] Origin 2: API Gateway (behavior: `/api/*`)
- [ ] CloudFront Function for SPA routing
- [ ] ACM certificate for `license.dauhai1012.online`
- [ ] CNAME in Route53

#### 1.6 SSM Parameters
- [ ] `/licensereminder/DATABASE_URL`
- [ ] `/licensereminder/COGNITO_USER_POOL_ID`
- [ ] `/licensereminder/COGNITO_CLIENT_ID`
- [ ] `/licensereminder/TELEGRAM_BOT_TOKEN`
- [ ] `/licensereminder/TELEGRAM_CHAT_ID`
- [ ] `/licensereminder/SES_FROM_EMAIL`

---

### Phase 2: API Layer — Lambda Functions (Week 2)

#### 2.1 Core Library
- [ ] `api/lib/db.ts` — PostgreSQL pool with connection reuse
- [ ] `api/lib/auth.ts` — Cognito JWT verification
- [ ] `api/lib/email.ts` — SES send helpers
- [ ] `api/lib/telegram.ts` — Bot API wrapper
- [ ] `api/lib/s3.ts` — Presigned URL generation
- [ ] `api/lib/logger.ts` — Structured JSON logging
- [ ] `api/lib/response.ts` — Response helpers
- [ ] `api/lib/schemas/` — Zod schemas (port from existing)

#### 2.2 Licenses API
- [ ] `GET /api/licenses` — List (paginated, filtered)
- [ ] `POST /api/licenses` — Create
- [ ] `GET /api/licenses/:id` — Get single
- [ ] `PUT /api/licenses/:id` — Update
- [ ] `DELETE /api/licenses/:id` — Soft delete
- [ ] `POST /api/licenses/bulk` — Bulk ops
- [ ] `POST /api/licenses/import` — CSV import
- [ ] `POST /api/licenses/:id/renew` — Renewal
- [ ] `GET/POST /api/licenses/:id/reminders`
- [ ] `GET /api/licenses/:id/activity`
- [ ] `GET/POST/DELETE /api/licenses/:id/attachments`
- [ ] `GET/POST /api/licenses/:id/notes`

#### 2.3 Reminders API
- [ ] `POST /api/reminders/trigger` — EventBridge cron
- [ ] `POST /api/reminders/send-now` — Manual send
- [ ] `POST /api/reminders/digest` — Digest email
- [ ] `GET /api/reminders/logs` — History

#### 2.4 Team API
- [ ] `GET /api/team/members`
- [ ] `POST /api/team/invite`
- [ ] `DELETE /api/team/members/:id`
- [ ] `PUT /api/team/members/:id`

#### 2.5 Org / Reports / Audit / Auth / Public
- [ ] Org settings CRUD
- [ ] PDF report generation
- [ ] Audit log (paginated)
- [ ] Auth setup-org + accept-invite
- [ ] Public renewal endpoints (HMAC)
- [ ] Health check

#### 2.6 SAM Template
- [ ] All Lambda functions defined
- [ ] HTTP API with CORS
- [ ] EventBridge cron
- [ ] IAM roles (SES, S3, SSM, RDS VPC)

---

### Phase 3: Frontend — React + Vite SPA (Week 3)

#### 3.1 Setup
- [ ] Vite + React 19 + TypeScript + React Router v7
- [ ] Zustand, `@aws-amplify/auth`, Zod
- [ ] Port `globals.css` (brand colors, Satoshi font)

#### 3.2 Auth Pages
- [ ] Login, Register, Forgot Password
- [ ] Accept Invite, Onboarding (create org)

#### 3.3 Protected Pages (port from Next.js)
- [ ] Dashboard, Licenses, License Detail, Analytics
- [ ] Reminders, Calendar, Team, Audit, Vendors, Settings

#### 3.4 Public Pages
- [ ] Renewal form, Renewal success

#### 3.5 Components (port existing)
- [ ] Sidebar, LicenseTable, LicenseForm, ReminderConfigPanel
- [ ] AttachmentPanel, AnalyticsCharts, CalendarView
- [ ] StatusBadge, ThemeProvider, ToastProvider, CsvImportModal

#### 3.6 API Client
- [ ] Fetch wrapper with Cognito token
- [ ] Error handling + toast integration

---

### Phase 4: Integration & Polish (Week 4)

- [ ] EventBridge → Reminder Lambda (daily 7am UTC)
- [ ] SES emails (HTML + plain text for Teams relay)
- [ ] Telegram notifications
- [ ] PDF generation in Lambda
- [ ] S3 file upload/download flow
- [ ] GitHub Actions CI/CD (OIDC auth)
- [ ] End-to-end testing

---

### Phase 5: Data Migration & Cutover (Week 5)

- [ ] `pg_dump` from Supabase → transform → import to RDS
- [ ] Bulk import users to Cognito (force password reset)
- [ ] Migrate attachments from Supabase Storage → S3
- [ ] DNS cutover: `license.dauhai1012.online` → CloudFront
- [ ] Monitor and validate

---

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Auth | Cognito | 50K MAU free, AWS-native JWT |
| Frontend | React + Vite | Static S3 deploy, no server needed |
| API pattern | Lambda per route | Fine-grained, clear SAM mapping |
| DB access | pg Pool (direct) | Simple at this scale |
| Email | SES | 62K/month free |
| IaC | SAM | Serverless-focused, simpler than CDK |
| CI/CD | GitHub Actions | OIDC to AWS, no stored secrets |
| State | Zustand | Lightweight, TypeScript-first |
| Org isolation | WHERE clauses | Simpler than RLS for Lambda |

---

## Monthly Cost

| Service | Cost |
|---|---|
| Lambda | $0 |
| API Gateway | $0 |
| Cognito | $0 |
| RDS t4g.micro | $0 (free tier) |
| SES | $0 |
| S3 | ~$0.50 |
| CloudFront | ~$0.50 |
| Route53 | $0.50 |
| CloudWatch | ~$0.50 |
| **Total** | **~$2/month** |

---

## Risks

| Risk | Mitigation |
|---|---|
| Lambda cold starts | ARM64 + small bundles + provisioned concurrency if needed |
| RDS public subnet | SG restricts to Lambda only; move to VPC for production |
| SES sandbox | Request production access in Week 1 |
| User password reset | Communicate before cutover |
| PDF timeout | 60s Lambda timeout, optimize template |
