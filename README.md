# Cahier des charges AWS ProServe

> **Confidentiality & IP Notice:** This repository contains the Cloud Modernization Blueprint, Infrastructure as Code (Terraform), Kubernetes manifests, and Architecture Decision Records (ADRs) for the **Ganesha (Ganesh'up)** production learning platform (published on the App Store by Lebourgmestre sàrl). To protect proprietary business logic, the full application source code remains in a private repository; a lightweight behavioral clone (`mock-api/`) exposing the exact production routes (`/api/health`, `/api/courses/share`, `/api/courses/cleanup`) is provided to validate the infrastructure locally via **LocalStack** and **k3d**.

---

## 1. Executive Summary & Engagement Context

**Ganesh'up** is an offline-first Flutter learning application backed by a **Node.js 20 / Typescript** REST API, **Prisma ORM**, **PostgreSQL 15**, and **Redis 7**.

Initially engineered for rapid time-to-market, the v1.0 production backend ran as a single-node `docker-compose` stack deployed via an atomic one-minute Bash script (`pg_dump` 3-2-1 backup, SHA-tagged build, container restart, and `/api/health` check). While effective for early adoption, an architectural audit conducted against the **AWS Well-Architected Framework** identified four structural bottlenecks preventing horizontal scale and zero-downtime operations.

---

## 2. Architectural Audit: "As-Is" Bottlenecks vs. "To-Be" AWS Target

| Bottleneck Identified ("As-Is") | Operational & Business Risk | AWS Modernization Solution ("To-Be") |
| :--- | :--- | :--- |
| **1. Stateful Local Disk Storage**<br>Course media (images/ & audio/) written to container a container env path (./uploads) | **Blocks Horizontal Scaling:** Running more than 1 API replica will causes 404 Not Found on GET /api/.../:token when requests hit a different container. | **Stateless Compute + Amazon S3** Offload media storage to **Amazon S3** with **S3 Lifecycle Policies** for automatic experiation of old files. |
