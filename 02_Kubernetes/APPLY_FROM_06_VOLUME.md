# 06_Volume부터 아래까지 재실습 (강사님 확인용 Runbook)

목표: `02_Kubernetes/06_Volume`부터 `14_CertManager`까지 순서대로 적용해서, 현재 Windows에서 보이는 `university` 네임스페이스 상태(마리아DB/레디스/department-api/vue)를 Mac에서도 재현.

> 참고: `06_Volume`의 `hostPath` 경로는 **Windows(Docker Desktop) 기준**으로 박혀 있어서, **Mac에서는 파일 수정이 필요**합니다. (아래 “Mac에서 hostPath 경로 수정”)

---

## 0) 사전 준비

- Kubernetes 클러스터 1개 (권장: Docker Desktop Kubernetes)
- `kubectl` 설치 및 클러스터 연결 확인
  - `kubectl cluster-info`

### (옵션) 완전 초기화 후 재실습

기존에 `university`가 남아있으면 아래로 지우고 시작할 수 있습니다.

```bash
kubectl delete ns university --ignore-not-found
kubectl delete pv mariadb-pv --ignore-not-found
kubectl delete pod emptydir-pod hostpath-pod --ignore-not-found
```

---

## 1) 네임스페이스 준비

이미 있으면 넘어가도 됩니다.

### macOS / Linux (zsh/bash)

```bash
kubectl get ns university >/dev/null 2>&1 || kubectl create ns university
```

### Windows (PowerShell)

```powershell
kubectl get ns university *> $null; if ($LASTEXITCODE -ne 0) { kubectl create ns university }
```

---

## 2) 06_Volume 적용 (Volume 실습 + MariaDB PV/PVC)

### 2-1) (옵션) emptyDir / hostPath 예제 Pod

```bash
kubectl apply -f 02_Kubernetes/06_Volume/emptydir-pod.yaml
kubectl apply -f 02_Kubernetes/06_Volume/hostpath-pod.yaml
kubectl get pod emptydir-pod hostpath-pod
```

### 2-2) MariaDB PV/PVC

```bash
kubectl apply -f 02_Kubernetes/06_Volume/mariadb-pv.yaml
kubectl apply -f 02_Kubernetes/06_Volume/mariadb-pvc.yaml
kubectl get pv mariadb-pv
kubectl -n university get pvc mariadb-pvc
```

---

## 3) 08_ConfigMap + 09_Secret 적용 (선행 리소스)

> `mariadb-deploy.yaml`, `redis-deploy.yaml`이 아래 리소스를 참조합니다.
>
> - ConfigMap: `global-config`, `redis-acl`
> - Secret: `mariadb-secret`

```bash
kubectl apply -f 02_Kubernetes/08_ConfigMap/global-config.yaml
kubectl apply -f 02_Kubernetes/08_ConfigMap/redis-acl-config.yaml

kubectl apply -f 02_Kubernetes/09_Secret/mariadb-secret.yaml
kubectl -n university get configmap global-config redis-acl
kubectl -n university get secret mariadb-secret

```

```
global-config.yaml
→ ConfigMap
→ TIME_ZONE=Asia/Seoul
→ MariaDB/Redis 공통 시간대 설정

mariadb-secret.yaml
→ Secret
→ MariaDB root 비밀번호 저장
→ MARIADB_ROOT_PASSWORD로 사용

redis-acl-config.yaml
→ ConfigMap
→ Redis ACL 파일 저장
→ Redis 사용자/비밀번호/권한 설정

ACL은 Kubernetes 리소스 종류가 아닙니다.
ACL은 Redis 내부 설정 내용이에요.

MariaDB 비밀번호 → Secret
공통 시간대 → ConfigMap
Redis ACL 파일 → ConfigMap

근데 보안적으로 더 좋은 구조는:
MariaDB 비밀번호 → Secret
공통 시간대 → ConfigMap
Redis ACL 파일 또는 Redis 비밀번호 → Secret

Kubernetes ConfigMap
        ↓
users.acl 파일을 만들어서 Pod 안에 넣어줌
        ↓
Redis가 그 users.acl 파일을 읽음
        ↓
Redis 사용자/권한 설정 적용

ConfigMap/Secret은 K8s가 설정을 전달하는 방식이고,
ACL/my.cnf/application.yml은 각 프로그램이 이해하는 설정 형식이다.
```

---

## 4) 07_MariaDB 적용

```bash
kubectl apply -f 02_Kubernetes/07_MariaDB/mariadb-deploy.yaml
kubectl apply -f 02_Kubernetes/07_MariaDB/mariadb-service.yaml
kubectl -n university get pod -l app=mariadb-app
kubectl -n university get svc mariadb-service
```

```
Pod = 실제 MariaDB 실행 중인 컨테이너
Service = MariaDB에 안정적으로 접속하기 위한 고정 주소

Service = 고정 주소 + Pod 묶기 + 내부 로드밸런싱


```

---

## 5) 10_Redis 적용

```bash
kubectl apply -f 02_Kubernetes/10_Redis/redis-deploy.yaml
kubectl apply -f 02_Kubernetes/10_Redis/redis-service.yaml
kubectl -n university get pod -l app=redis-app
kubectl -n university get svc redis-service
```

```
redis-acl ConfigMap
        ↓
users.acl 파일로 컨테이너 안에 마운트
        ↓
/usr/local/etc/redis/users.acl
        ↓
args에서 redis-server --aclfile 경로로 지정
        ↓
Redis가 시작하면서 ACL 설정 읽음

```

```
먼저 Redis Pod 접속:
kubectl exec -it -n university deploy/redis-deploy -- redis-cli

beyond 사용자로 로그인
AUTH beyond beyond

SCAN으로 refresh:* 조회
SCAN 0 MATCH refresh:*
```

---

---

## 6) 11_DepartmentService 적용

> `department-api-deploy.yaml`이 사용하는 이미지가 로컬에 없으면 `ImagePullBackOff`가 발생할 수 있으므로, 먼저 Docker 이미지를 빌드합니다.

### 6-1) DepartmentService 이미지 빌드

```bash
cd 02_Kubernetes/11_DepartmentService
docker build -t jin604/department-service:1.0 .
cd ../../..
```

이미지 확인:

```bash
docker images | grep department-service
```

### 6-2) DepartmentService Deployment / Service 적용

```bash
kubectl apply -f 02_Kubernetes/11_DepartmentService/department-api-deploy.yaml
kubectl apply -f 02_Kubernetes/11_DepartmentService/department-api-service.yaml
kubectl -n university get pod -l app=department-api
kubectl -n university get svc department-api-service
```

이미 Deployment가 `ImagePullBackOff` 상태로 떠 있었다면, 이미지 빌드 후 다시 시작합니다.

```bash
kubectl rollout restart deploy/department-api-deploy -n university
kubectl rollout status deploy/department-api-deploy -n university
```

---

---

## 7) 12_UniversityVue 적용

> `university-vue-deploy.yaml`이 사용하는 이미지가 로컬에 없으면 `ImagePullBackOff`가 발생할 수 있으므로, 먼저 Docker 이미지를 빌드합니다.

### 7-1) UniversityVue 이미지 빌드

```bash
cd 02_Kubernetes/12_UniversityVue
docker build -t jin604/university-vue:1.0 .
cd ../../..
```

이미지 확인:

```bash
docker images | grep university-vue
```

### 7-2) UniversityVue Deployment / Service 적용

```bash
kubectl apply -f 02_Kubernetes/12_UniversityVue/university-vue-deploy.yaml
kubectl apply -f 02_Kubernetes/12_UniversityVue/university-vue-service.yaml
kubectl -n university get pod -l app=university-vue
kubectl -n university get svc university-vue-service
```

이미 Deployment가 `ImagePullBackOff` 상태로 떠 있었다면, 이미지 빌드 후 다시 시작합니다.

```bash
kubectl rollout restart deploy/university-vue-deploy -n university
kubectl rollout status deploy/university-vue-deploy -n university
```

---

---

## 8) 여기까지 결과 확인 (현재 질문에 나온 상태)

```bash
kubectl get all -n university
```

---

## 9) 13_Ingress 컨트롤러+ 14_CertManager (Helm + apply 혼합)

> 이 파트는 `kubectl apply`만으로는 안 되고, **Ingress-NGINX / cert-manager는 Helm 설치가 필요**합니다.
> 강의에서 사용한 차트 Repo/버전이 있을 수 있으니 강사님께 아래 커맨드가 맞는지 확인받아주세요.

### 9-1) ingress-nginx 설치(Helm)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f 02_Kubernetes/13_Ingress/ingress-nginx-values.yaml
kubectl -n ingress-nginx get pods
```

### 9-2) cert-manager 설치(Helm)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  -f 02_Kubernetes/14_CertManager/cert-manager-values.yaml
kubectl -n cert-manager get pods
```

### 9-3) ClusterIssuer + Ingress 적용(kubectl apply)

```bash
kubectl apply -f 02_Kubernetes/14_CertManager/selfsigned-cluster-issuer.yaml
kubectl apply -f 02_Kubernetes/13_Ingress/university-ingress.yaml
kubectl -n university get ingress university-ingress
```

---

## 10) Mac에서 hostPath 경로 수정 (강사님 확인 포인트)

아래 파일들은 `hostPath.path`가 Windows 경로(`/run/desktop/mnt/host/c/...`)로 되어 있어서 Mac에서는 그대로 쓰기 어렵습니다.

- `02_Kubernetes/06_Volume/hostpath-pod.yaml`
- `02_Kubernetes/06_Volume/mariadb-pv.yaml`

강의 환경이 **Docker Desktop Kubernetes**라면, 보통 Mac에서는 아래처럼 “Users 경로”로 바꿔야 합니다(정확한 값은 환경마다 다를 수 있음).

- 예시(개념): `/run/desktop/mnt/host/Users/<mac_username>/...`

강사님께 질문할 것(핵심):

1. Mac(Docker Desktop)에서 `hostPath`는 어떤 경로로 잡는 게 정답인지?
2. 아니면 `hostPath` 대신 다른 방식(예: local-path StorageClass, emptyDir 등)으로 진행하는지?

---

## 11) 문제 생길 때 확인 커맨드

```bash
kubectl -n university get pod -o wide
kubectl -n university describe pod <pod-name>
kubectl -n university logs <pod-name>
kubectl get pv mariadb-pv
kubectl -n university get pvc mariadb-pvc -o wide
```
