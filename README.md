# Deploy a Complex 3-Tier Application with Minimal Kubernetes

**A production-style 3-tier web application (Next.js frontend, Node.js/Express backend, MongoDB Atlas database) running on Kubernetes with just 8 small YAML files.**

This beginner-friendly project shows that you don't need Helm, operators or dozens of manifests to run a real multi-tier app. It uses only the core Kubernetes building blocks (Namespace, Deployment, Service, ConfigMap, Secret and Ingress) on a local cluster running on **WSL2**.

> **Note:** This Repo is just like a Template for Beginners to Understand. This repo contains **only the Kubernetes and Docker configuration**. The application source code is not included. The app runs from pre-built Docker images, so you don't need the source to follow along. 
---

## Architecture

```
                         Browser
                            │
                   http://my-k8s-app.local
                            │
                ┌───────────▼────────────┐
                │  Ingress (NGINX)       │   k8s/ingress.yaml
                │  /     → frontend      │
                │  /api  → backend       │
                └─────┬────────────┬─────┘
                      │            │
        ┌─────────────▼───┐   ┌────▼──────────────┐
        │ frontend-service│   │ backend-service   │
        │ NodePort :3000  │   │ ClusterIP :3001   │
        └─────────┬───────┘   └────┬──────────────┘
                  │                │
        ┌─────────▼───────┐   ┌────▼──────────────┐
        │ Frontend Pods×2 │   │ Backend Pods ×2   │◄── ConfigMap (settings)
        │ Next.js         │   │ Node.js / Express │◄── Secret (passwords)
        └─────────────────┘   └────┬──────────────┘
                                   │
                          MongoDB Atlas (cloud)
```

Everything runs inside the `my-k8s-app` **namespace**.

---

## How a request flows

A common assumption is that traffic goes **browser → frontend pod → backend pod → DB**, with the frontend passing requests to the backend. **That's not how this app works.** The frontend and backend pods never talk to each other directly.

**The frontend pod only serves the UI.** It sends the browser the HTML, CSS and JavaScript. That JavaScript then runs **inside the user's browser**, which fetches the data with separate requests.

```
Step 1 – Load the UI
Browser ──GET http://my-k8s-app.local/────────► Ingress ──► frontend-service ──► frontend pod
Browser ◄──────────── HTML + CSS + JavaScript ──────────────────────────────────────┘
        (the frontend pod's job is done)

Step 2 – The UI, now running in the browser, fetches data
Browser ──GET http://my-k8s-app.local/api/v1/events──► Ingress ──► backend-service ──► backend pod ──► MongoDB
Browser ◄──────────────────────── JSON data ────────────────────────────────────────────────┘
        (the UI shows the data on the page)
```

Each kind of request goes to a different pod, and the **Ingress** decides which one by looking at the URL path:

| Request | Routed to | Returns |
|---|---|---|
| `my-k8s-app.local/` | frontend pod | The UI (page + JavaScript) |
| `my-k8s-app.local/api/v1/...` | backend pod | The data (JSON) |

**Why does this work?** The frontend is built with `NEXT_PUBLIC_API_URL=/api/v1`. Because that URL is *relative*, the browser sends API calls to the same host the page came from (`my-k8s-app.local`), and the Ingress routes them to the backend.

**See it yourself:** open the app, press **F12**, and go to the **Network** tab. The page loads first, followed by separate `/api/v1/...` requests that return JSON.

> **Note:** Next.js *can* also fetch data on the server before sending the page (server-side rendering). In that case the frontend pod calls `backend-service:3001` inside the cluster. This app fetches data in the browser, so the flow above applies.

> **Use the Ingress URL.** If you open the frontend through the NodePort (`http://localhost:30080`), the UI loads, but API calls go to `localhost:30080/api/v1/...`. That's the frontend pod, which has no API, so data won't load. The NodePort is only useful for debugging the frontend on its own.

---

## What's in this repo

```
.
├── docker/
│   ├── backend.Dockerfile      # Multi-stage build: compile TypeScript, then slim runtime image
│   └── frontend.Dockerfile     # Multi-stage build: Next.js standalone output
└── k8s/
    ├── namespace.yaml          # Isolated space for all resources
    ├── ingress.yaml            # Routes / to frontend and /api to backend
    ├── backend/
    │   ├── configmap.yaml      # Non-secret settings (port, URLs, limits)
    │   ├── secret.example.yaml # Template for passwords and keys
    │   ├── deployment.yaml     # 2 replicas, health probes, CPU/memory limits
    │   └── service.yaml        # ClusterIP: reachable only inside the cluster
    └── frontend/
        ├── deployment.yaml     # 2 replicas, health probes, CPU/memory limits
        └── service.yaml        # NodePort 30080: reachable from your machine
```

## Kubernetes concepts used

| Concept | Where | Why |
|---|---|---|
| **Namespace** | `namespace.yaml` | Keeps this project's resources separate from everything else |
| **Deployment** | `*/deployment.yaml` | Runs 2 copies (replicas) of each app and restarts them if they crash |
| **Service (ClusterIP)** | `backend/service.yaml` | Gives the backend a stable internal address; it isn't exposed outside |
| **Service (NodePort)** | `frontend/service.yaml` | Exposes the frontend on port `30080` of the node |
| **Ingress** | `ingress.yaml` | One entry point that routes by URL path |
| **ConfigMap** | `backend/configmap.yaml` | Settings injected as environment variables |
| **Secret** | `backend/secret.example.yaml` | Passwords and keys, kept apart from normal config |
| **Liveness / Readiness probes** | `*/deployment.yaml` | Kubernetes checks `/api/v1/health` to know whether a pod is alive and ready for traffic |
| **Resource requests / limits** | `*/deployment.yaml` | Reserves CPU/memory and stops one pod from using it all |
| **imagePullSecrets** | `*/deployment.yaml` | Lets the cluster pull images from a private Docker Hub repo |

---

## Prerequisites

- Windows with **WSL2** (Ubuntu)
- **Docker** (Docker Desktop with WSL2 backend, or Docker Engine inside WSL)
- A local Kubernetes cluster:**minikube** or **kind**
- `kubectl`
- **NGINX Ingress Controller** installed in the cluster
- A **MongoDB Atlas** connection string (free tier works)

## Deploy step by step

**1. Create the namespace**
```bash
kubectl apply -f k8s/namespace.yaml
```

**2. Create the Docker Hub pull secret** (needed only if your images are private)
```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-username=<your-dockerhub-username> \
  --docker-password=<your-dockerhub-token> \
  -n my-k8s-app
```

**3. Create the app secret**
```bash
cp k8s/backend/secret.example.yaml k8s/backend/secret.yaml
# edit secret.yaml and fill in real values
kubectl apply -f k8s/backend/secret.yaml
```

**4. Apply config, deployments, services and ingress**
```bash
kubectl apply -f k8s/backend/configmap.yaml
kubectl apply -f k8s/backend/deployment.yaml -f k8s/backend/service.yaml
kubectl apply -f k8s/frontend/
kubectl apply -f k8s/ingress.yaml
```

**5. Point `my-k8s-app.local` at your cluster**

Add this line to your hosts file (`C:\Windows\System32\drivers\etc\hosts` on Windows, `/etc/hosts` in WSL):
```
127.0.0.1   my-k8s-app.local
```
On minikube, use the output of `minikube ip` instead of `127.0.0.1`.

**6. Open the app**: http://my-k8s-app.local

(http://localhost:30080 also loads the UI, but data won't load there. See [How a request flows](#how-a-request-flows).)

## Check that it's working

```bash
kubectl get all -n my-k8s-app                   # pods, services, deployments
kubectl get ingress -n my-k8s-app
kubectl describe pod <pod-name> -n my-k8s-app   # events: probe failures, image pull errors
kubectl logs -f deploy/backend-deployment -n my-k8s-app
```

## Common problems

| Symptom | Likely cause |
|---|---|
| `ImagePullBackOff` | Wrong image name, or the `dockerhub-secret` is missing or incorrect |
| `CrashLoopBackOff` (backend) | Bad `MONGODB_URI`, or Atlas isn't allowing your IP |
| `OOMKilled` | Memory limit too low; raise `resources.limits.memory` |
| Pod `Running` but not `Ready` | Readiness probe failing; check `kubectl logs` |
| `my-k8s-app.local` doesn't load | Hosts file entry missing, or Ingress controller not installed |

---

## Run it with your own app

These manifests work with any frontend/backend pair that meets these conditions:

| | Frontend | Backend |
|---|---|---|
| Container port | `3000` | `3001` |
| Health check path | `/` | `/api/v1/health` |
| API prefix | — | `/api` |

Build and push your images with the Dockerfiles in `docker/`:
```bash
docker build -f docker/backend.Dockerfile  -t <user>/my_k8s_app:backend-v1  ./your-backend
docker build -f docker/frontend.Dockerfile -t <user>/my_k8s_app:frontend-v1 ./your-frontend
docker push <user>/my_k8s_app:backend-v1
docker push <user>/my_k8s_app:frontend-v1
```
Then change the `image:` lines in both `deployment.yaml` files.

## What I learned

- Writing Deployments, Services, ConfigMaps, Secrets and Ingress from scratch
- Why the backend uses ClusterIP (internal) while the frontend is exposed
- Using health probes so Kubernetes only sends traffic to ready pods
- Keeping secrets out of Git with a template file
- Multi-stage Docker builds for smaller images
- Running Kubernetes locally on WSL2

## Next steps

- [ ] Package the manifests as a Helm chart
- [ ] Add a HorizontalPodAutoscaler
- [ ] Add CI/CD with GitHub Actions
- [ ] Run MongoDB inside the cluster with a StatefulSet and PersistentVolume
