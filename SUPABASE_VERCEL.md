# Supabase + Vercel deployment

## 1. Supabase schema

Run `server/supabase/schema.sql` in the Supabase SQL Editor.

## 2. Deploy the API

Create a second Vercel project from the same repository with `server` as the root directory:

```bash
cd server
vercel --prod
```

Set these environment variables in that Vercel API project for Production:

```env
DATABASE_URL=your-supabase-postgres-connection-string
JWT_SECRET=long-random-secret
SEED_DEMO_DATA=false
BOOTSTRAP_ADMIN_USERNAME=admin
BOOTSTRAP_ADMIN_PASSWORD=at-least-12-characters
BOOTSTRAP_ADMIN_NAME=Ana Yonetici
```

The API health endpoint is:

```text
https://your-api-project.vercel.app/api/health
```

## 3. Connect the frontend

In the frontend Vercel project, set:

```env
VITE_API_URL=https://your-api-project.vercel.app/api
```

Then redeploy the frontend:

```bash
cd client
vercel --prod
```

Never put `DATABASE_URL`, `JWT_SECRET`, or a Supabase service-role key in frontend variables.
