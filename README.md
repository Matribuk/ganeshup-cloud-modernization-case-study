# Cahier des charges AWS ProServe

> **Confidentiality & IP Notice:** This repository contains the Cloud Modernization Blueprint, Infrastructure as Code (Terraform), Kubernetes manifests, and Architecture Decision Records (ADRs) for the **Ganesha (Ganesh'up)** production learning platform (published on the App Store by Lebourgmestre sàrl). To protect proprietary business logic, the full application source code remains in a private repository; a lightweight behavioral clone (`mock-api/`) exposing the exact production routes (`/api/health`, `/api/courses/share`, `/api/courses/cleanup`) is provided to validate the infrastructure locally via **LocalStack** and **k3d**.

---

## 1. Executive Summary & Engagement Context

**Ganesh'up** is an offline-first Flutter learning application backed by a **Node.js 20 / Typescript** REST API, **Prisma ORM**, **PostgreSQL 15**, and **Redis 7**.

Initially engineered for rapid time-to-market, the v1.0 production backend ran as a single-node `docker-compose` stack deployed via an atomic one-minute Bash script (`pg_dump` 3-2-1 backup, SHA-tagged build, container restart, and `/api/health` check). While effective for early adoption, an architectural audit conducted against the **AWS Well-Architected Framework** identified four structural bottlenecks preventing horizontal scale and zero-downtime operations.

---

## 2. Architectural Audit: "As-Is" Bottlenecks vs. "To-Be" AWS Target

> **Bottleneck identified by Stateful, CPU-RAM-Bandwidth, BDD-Lifecycle, Administravie Process**

| Bottleneck Identified ("As-Is") | Operational & Business Risk | AWS Modernization Solution ("To-Be") |
| :--- | :--- | :--- |
| **1. Stateful Local Disk Storage**<br>Course media (images/ & audio/) written to container a container env path (./uploads) | **Blocks Horizontal Scaling:** Running more than 1 API replica will causes 404 Not Found on GET /api/.../:token when requests hit a different container. | **Stateless Compute + Amazon S3** Offload media storage to **Amazon S3** with **S3 Lifecycle Policies** for automatic experiation of old files. |
| **2. Heavy 50MB Base64 Payloads**<br>POST /api/.../share ingests and decode up to 50MB of Base64 JSON in-memory. | **Event-Loop Starvation & Out of Memory:** Base64 decoding spikes Node.js memory and block concurrent /api/auth requests. | **S3 Predesigned URLs & Async Workers:** Decouple binary uploads from JSON metadata (shared_courses table) and process media asynchronously via **SQS + Lambda.** |
| **3. Single-Node Deployment & Prisma Migrations** <br>Atomic restart script + manual npx prisma migrate deploy. | **Deployment Downtime:** Brief connection drops during container restarts interrupt active mobile sync queues. | **Kubernetes (k3d/EKS) RollingUpdate:** 3 stateless replicas (maxUnavailable: 0) gated by /api/health on port 3000 + K8s InitContainer for Prisma migrations. |
