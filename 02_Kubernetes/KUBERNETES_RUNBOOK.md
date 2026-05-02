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
cd 02_Kubernetes/13_Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f ingress-nginx-values.yaml
kubectl -n ingress-nginx get pods
cd ../..
```

명령어 의미:

```text
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
→ Helm에게 ingress-nginx chart 저장소 주소를 등록한다.
→ Git repo에 저장하는 것이 아니라, 내 Mac의 Helm 설정에 저장된다.

helm repo update
→ 등록된 Helm chart 저장소의 최신 목록을 가져온다.

kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
→ ingress-nginx namespace가 없으면 만들고, 이미 있으면 그대로 둔다.

helm install
→ Helm chart를 Kubernetes에 새로 설치한다.

ingress-nginx
→ 설치 이름이다. Helm에서는 이것을 release 이름이라고 부른다.

ingress-nginx/ingress-nginx
→ 앞의 ingress-nginx는 Helm repo 이름이고,
  뒤의 ingress-nginx는 그 repo 안에 있는 chart 이름이다.

-n ingress-nginx
→ ingress-nginx namespace에 설치한다.

-f ingress-nginx-values.yaml
→ chart의 기본 설정 대신 이 values 파일의 설정을 적용해서 설치한다.
```

Ingress와 nginx 관계:

```text
Kubernetes의 Ingress는 라우팅 규칙만 정의한다.
Ingress 자체는 실제 HTTP/HTTPS 요청을 처리하지 않는다.

따라서 Ingress 규칙을 읽고 실제로 트래픽을 Service로 보내주는 프로그램이 필요하다.
그 프로그램을 Ingress Controller라고 한다.

이번 실습에서는 NGINX 기반 Ingress Controller를 사용한다.
그래서 이름이 ingress-nginx이다.
```

정리:

```text
Ingress = 라우팅 규칙
Ingress Controller = Ingress 규칙을 실제로 처리하는 서버
ingress-nginx = NGINX로 만든 Ingress Controller
Helm chart = ingress-nginx를 Kubernetes에 설치하기 위한 패키지
values.yaml = chart 설치 옵션을 바꾸는 설정 파일
```

이번 실습에서 중요한 값:

```yaml
controller:
  service:
    type: NodePort
    nodePorts:
      http: "30080"
      https: "30443"
```

의미:

```text
ingress-nginx controller Service를 NodePort 타입으로 노출한다.

HTTP 요청은 30080 포트로 받는다.
HTTPS 요청은 30443 포트로 받는다.

그래서 브라우저에서는 아래처럼 접근한다.
```

```text
http://university.beyond.com:30080
https://university.beyond.com:30443
```

참고:

```text
helm install은 처음 설치할 때 사용한다.
이미 같은 release 이름이 있으면 에러가 날 수 있다.

이미 설치된 것을 다시 적용하거나 수정하려면 아래처럼 upgrade --install을 쓸 수 있다.
```

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f ingress-nginx-values.yaml
```

### 9-2) cert-manager 설치(Helm)

```bash
cd 02_Kubernetes/14_CertManager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager \
  --create-namespace \
  -f cert-manager-values.yaml
kubectl -n cert-manager get pods
cd ../..
```

명령어 의미:

```text
helm repo add jetstack https://charts.jetstack.io
→ Helm에게 cert-manager chart가 있는 jetstack 저장소 주소를 등록한다.

helm repo update
→ 등록된 Helm chart 저장소의 최신 목록을 가져온다.

helm upgrade --install
→ cert-manager release가 이미 있으면 업그레이드하고,
  없으면 새로 설치한다.

cert-manager
→ 설치 이름이다. Helm에서는 이것을 release 이름이라고 부른다.

jetstack/cert-manager
→ 앞의 jetstack은 Helm repo 이름이고,
  뒤의 cert-manager는 그 repo 안에 있는 chart 이름이다.

-n cert-manager
→ cert-manager namespace에 설치한다.

--create-namespace
→ cert-manager namespace가 없으면 Helm이 자동으로 만든다.

-f cert-manager-values.yaml
→ chart의 기본 설정 대신 이 values 파일의 설정을 적용해서 설치한다.
```

cert-manager 역할:

```text
Ingress에서 HTTPS를 사용하려면 TLS 인증서가 필요하다.
cert-manager는 Kubernetes 안에서 인증서 발급과 갱신을 관리해주는 Controller이다.

이번 실습에서는 self-signed ClusterIssuer를 사용해서
로컬 테스트용 TLS Secret을 자동으로 만들게 한다.
```

정리:

```text
cert-manager = 인증서 발급/관리 Controller
ClusterIssuer = 어떤 방식으로 인증서를 발급할지 정하는 클러스터 범위 리소스
Certificate = cert-manager가 관리하는 인증서 요청 리소스
TLS Secret = 실제 인증서와 개인키가 저장되는 Secret
cert-manager-values.yaml = cert-manager chart 설치 옵션 파일
```

values 파일 출처:

```text
cert-manager-values.yaml은 보통 Helm chart의 기본 values를 가져와서 만든다.
```

```bash
helm show values jetstack/cert-manager > cert-manager-values.yaml
```

이번 실습에서 중요한 값:

```yaml
crds:
  enabled: true
```

의미:

```text
cert-manager가 사용하는 CRD를 Helm 설치 시 같이 설치한다.
처음 설치하는 환경이면 true가 필요하다.
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

---

## 12) Docker Desktop Kubernetes 개념 정리

### 12-1) Docker Desktop에서 Node가 보이는 이유

```bash
kubectl get no
```

예시:

```text
NAME             STATUS   ROLES           AGE    VERSION
docker-desktop   Ready    control-plane   5h9m   v1.34.1
```

`docker-desktop`은 내가 직접 만든 앱 리소스가 아니라, Docker Desktop이 만든 Kubernetes Node입니다.

정확한 관계:

```text
Cluster
└── Node: docker-desktop
    ├── Pod: department-api-...
    ├── Pod: mariadb-...
    ├── Pod: redis-...
    └── Pod: university-vue-...
```

정리:

```text
Node = Pod들이 실행되는 서버/머신
Pod = 컨테이너를 담는 Kubernetes의 최소 실행 단위
Container = 실제 애플리케이션 프로세스가 실행되는 단위
Cluster = Node들의 묶음
```

즉, Node는 "Pod들의 집합"이라기보다 **Pod들이 올라가는 실행 머신**입니다.

Pod가 어느 Node에 올라갔는지 확인:

```bash
kubectl get pods -A -o wide
```

Docker Desktop Kubernetes는 보통 Node가 1개입니다.

```text
모든 Pod의 NODE 컬럼이 docker-desktop으로 표시됨
```

### 12-2) macOS에서 Docker와 Kubernetes가 동작하는 구조

Docker는 Linux 커널 기능을 사용해서 컨테이너를 실행합니다.

macOS는 Linux 커널이 아니기 때문에, Docker Desktop은 내부에 Linux VM을 띄우고 그 안에서 컨테이너를 실행합니다.

Docker만 사용할 때:

```text
macOS
└── Docker Desktop
    └── Linux VM
        └── Container
```

Docker Desktop Kubernetes를 사용할 때:

```text
macOS
└── Docker Desktop
    └── Linux VM
        ├── container runtime
        ├── Kubernetes control plane
        └── Node: docker-desktop
            ├── Pod
            │   └── Container
            ├── Pod
            │   └── Container
            └── Pod
                └── Container
```

역할 정리:

```text
Docker = 컨테이너를 실행하는 도구
Kubernetes = 컨테이너들을 원하는 상태로 계속 관리하는 오케스트레이터
```

Kubernetes가 해주는 일:

```text
이 컨테이너 3개 띄워줘
죽으면 다시 살려줘
Service 이름으로 접근하게 해줘
어느 Node에 배치할지 정해줘
```

### 12-3) 내가 만들지 않은 기본 리소스

```bash
kubectl get all
```

namespace를 지정하지 않으면 기본적으로 `default` namespace를 봅니다.

예시:

```text
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   5h9m
```

`service/kubernetes`는 Kubernetes가 자동으로 만드는 기본 Service입니다.

의미:

```text
클러스터 내부 Pod들이 Kubernetes API Server에 접근하기 위한 기본 Service
```

내가 만든 university 리소스는 namespace를 지정해서 봅니다.

```bash
kubectl get all -n university
```

전체 namespace를 보려면:

```bash
kubectl get all -A
```

namespace 목록:

```bash
kubectl get ns
```

Kubernetes 리소스 종류와 단축어 보기:

```bash
kubectl api-resources
```

예시 단축어:

```text
pods         po
services     svc
deployments  deploy
replicasets  rs
namespaces   ns
nodes        no
```

### 12-4) ClusterIP라서 localhost로 바로 접속이 안 되는 경우

예시:

```text
service/department-api-service   ClusterIP   ...   8088/TCP
service/university-vue-service   ClusterIP   ...   80/TCP
```

`ClusterIP`는 클러스터 내부 전용 Service입니다.

그래서 내 Mac 브라우저에서 바로 아래처럼 접근할 수 없습니다.

```text
http://localhost:8088
```

테스트하려면 port-forward를 사용합니다.

Department API:

```bash
kubectl port-forward -n university service/department-api-service 8088:8088
```

접속:

```text
http://localhost:8088
```

University Vue:

```bash
kubectl port-forward -n university service/university-vue-service 8080:80
```

접속:

```text
http://localhost:8080
```

외부에서 계속 접근해야 하면 Service를 `NodePort`로 바꾸거나 Ingress를 사용합니다.

### 12-5) 잠깐 끄기와 다시 켜기

Kubernetes에는 namespace를 "stop"하는 명령이 따로 없습니다.

앱만 잠깐 끄고 싶으면 Deployment replica를 0으로 줄입니다.

```bash
kubectl scale deployment --all --replicas=0 -n university
```

이 경우:

```text
Pod는 사라짐
Deployment는 남음
Service는 남음
ConfigMap/Secret/PVC는 남음
```

다시 켤 때는 원래 replica 수를 맞춰서 올립니다.

현재 실습 기준:

```bash
kubectl scale deployment department-api-deploy --replicas=3 -n university
kubectl scale deployment mariadb-deploy --replicas=1 -n university
kubectl scale deployment redis-deploy --replicas=1 -n university
kubectl scale deployment university-vue-deploy --replicas=1 -n university
```

한 번에 전부 1개로 올릴 수도 있지만:

```bash
kubectl scale deployment --all --replicas=1 -n university
```

이렇게 하면 `department-api-deploy`도 1개만 뜹니다.

`department-api`는 원래 3개였으므로 따로 3개로 올려야 합니다.

### 12-6) Docker Desktop Kubernetes Stop 버튼

Docker Desktop의 Kubernetes 화면에 있는 Stop은 `university` namespace만 끄는 버튼이 아닙니다.

의미:

```text
Docker Desktop Kubernetes 클러스터 전체 정지
```

영향:

```text
university namespace 앱들 멈춤
kube-system 구성요소도 멈춤
kubectl get all 같은 명령이 안 될 수 있음
Docker Compose 컨테이너는 계속 살아있을 수 있음
이미지/매니페스트/리소스 정의는 보통 삭제되지 않음
```

다시 켜려면 Docker Desktop에서 Kubernetes를 다시 Start/Install/Enable 합니다.

주의할 버튼:

```text
Reset Kubernetes Cluster
Clean / Purge data
Factory reset
```

이런 초기화 계열은 리소스가 삭제될 수 있습니다.

다시 켠 뒤 확인:

```bash
kubectl get ns
kubectl get all -n university
```

### 12-7) Docker Compose로 올린 컨테이너 끄기

Kubernetes와 Docker Compose는 별개입니다.

`kubectl scale`로 Docker Compose 컨테이너는 꺼지지 않습니다.

Compose 파일명이 기본값이면:

```bash
docker compose down
```

현재 biddinggo 예시처럼 파일명이 `docker-compose.local.yml`이면:

```bash
docker compose -f docker-compose.local.yml down
```

컨테이너만 멈추고 삭제하지 않으려면:

```bash
docker compose -f docker-compose.local.yml stop
```

다시 켜기:

```bash
docker compose -f docker-compose.local.yml up -d
```

주의:

```bash
docker compose down -v
```

`-v`는 volume까지 지울 수 있으므로 DB 데이터가 필요하면 사용하지 않습니다.

### 12-8) 리소스 확인 명령어

Kubernetes metrics-server가 없으면 아래 명령은 실패할 수 있습니다.

```bash
kubectl top nodes
kubectl top pods -A
```

오류 예시:

```text
error: Metrics API not available
```

이건 앱 문제가 아니라 metrics-server가 없다는 뜻입니다.

Docker 컨테이너별 메모리 확인:

```bash
docker stats
```

한 번만 출력:

```bash
docker stats --no-stream
```

macOS 프로세스별 메모리 Top:

```bash
top -o mem
```

한 번만 보기:

```bash
ps -axo pid,rss,%mem,comm | sort -nrk2 | head -30
```

스왑 확인:

```bash
sysctl vm.swapusage
```

macOS의 `fastfetch`에서 보이는 Swap total은 고정 최대치라기보다 현재 만들어진 swapfile 총량에 가깝습니다.

메모리 압박이 더 커지면 swap total이 더 늘어날 수 있습니다.

### 12-9) 이번 university 앱의 대략적인 메모리 감각

`docker stats` 기준 예시:

```text
university-vue        약 12MiB
department-api #1    약 220MiB
department-api #2    약 220MiB
department-api #3    약 220MiB
redis                 약 10~40MiB
mariadb               약 130~150MiB
```

대략 합계:

```text
약 800~900MiB
```

대부분은 `department-api` 3개가 사용합니다.

`docker images`의 `DISK USAGE`는 디스크 용량이고, 실행 중 메모리는 `docker stats`의 `MEM USAGE`를 봅니다.

### 12-10) Ingress까지 붙이면 요청 흐름이 어떻게 되는가

Service가 `ClusterIP`이면 클러스터 내부에서만 접근됩니다.

Ingress를 붙이면 외부 요청을 받아서, 요청 Host/Path에 따라 내부 Service로 보내는 입구를 만들 수 있습니다.

전체 흐름:

```text
브라우저
  ↓
Ingress Controller Service(NodePort: 30080/30443)
  ↓
Ingress rule(university-ingress)
  ↓
ClusterIP Service
  ↓
Pod
  ↓
Container
```

현재 실습 파일 기준:

```text
api.department.beyond.com
  ↓
department-api-service:8088
  ↓
department-api Pod 3개 중 하나

university.beyond.com
  ↓
university-vue-service:80
  ↓
university-vue Pod
```

Ingress 파일:

```bash
02_Kubernetes/13_Ingress/university-ingress.yaml
```

핵심 설정:

```yaml
spec:
  ingressClassName: nginx
  tls:
    - secretName: university-tls-secret
      hosts:
        - api.department.beyond.com
        - university.beyond.com
  rules:
    - host: api.department.beyond.com
      http:
        paths:
          - path: "/"
            backend:
              service:
                name: department-api-service
                port:
                  number: 8088
    - host: university.beyond.com
      http:
        paths:
          - path: /
            backend:
              service:
                name: university-vue-service
                port:
                  number: 80
```

여기서 중요한 점:

```text
Ingress 자체는 트래픽을 직접 처리하지 않음
Ingress Controller가 Ingress 규칙을 읽고 실제 라우팅을 처리함
```

그래서 먼저 ingress-nginx controller가 설치되어 있어야 합니다.

```bash
cd 02_Kubernetes/13_Ingress
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f ingress-nginx-values.yaml
cd ../..
```

현재 values 파일 기준으로 ingress-nginx controller Service는 `NodePort`입니다.

```text
HTTP  → 30080
HTTPS → 30443
```

확인:

```bash
kubectl get svc -n ingress-nginx
```

예상 형태:

```text
ingress-nginx-controller   NodePort   ...   80:30080/TCP,443:30443/TCP
```

Ingress 적용:

```bash
kubectl apply -f 02_Kubernetes/14_CertManager/selfsigned-cluster-issuer.yaml
kubectl apply -f 02_Kubernetes/13_Ingress/university-ingress.yaml
```

확인:

```bash
kubectl get ingress -n university
kubectl describe ingress university-ingress -n university
```

### 12-11) Ingress 도메인 테스트를 위한 hosts 설정

Ingress rule은 Host 이름을 보고 라우팅합니다.

현재 Host:

```text
api.department.beyond.com
university.beyond.com
```

실제 DNS가 없으면 내 Mac의 `/etc/hosts`에 직접 등록해야 합니다.

```bash
sudo vi /etc/hosts
```

추가:

```text
127.0.0.1 api.department.beyond.com
127.0.0.1 university.beyond.com
```

Docker Desktop Kubernetes에서 NodePort로 열려 있으므로 테스트 URL은 포트를 붙입니다.

Vue:

```text
http://university.beyond.com:30080
https://university.beyond.com:30443
```

API:

```text
http://api.department.beyond.com:30080
https://api.department.beyond.com:30443
```

curl로 Host 라우팅 테스트:

```bash
curl -I http://university.beyond.com:30080
curl -I http://api.department.beyond.com:30080
```

hosts를 수정하지 않고 테스트하려면 Host 헤더를 직접 넣을 수도 있습니다.

```bash
curl -I -H "Host: university.beyond.com" http://localhost:30080
curl -I -H "Host: api.department.beyond.com" http://localhost:30080
```

### 12-12) cert-manager와 self-signed 인증서

현재 Ingress에는 아래 annotation이 있습니다.

```yaml
cert-manager.io/cluster-issuer: selfsigned-cluster-issuer
```

그리고 ClusterIssuer는 self-signed 방식입니다.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

의미:

```text
cert-manager가 university-tls-secret이라는 TLS Secret을 자동 생성
인증서는 self-signed라서 브라우저에서 신뢰 경고가 날 수 있음
학습/로컬 테스트용으로는 가능
운영에서는 Let's Encrypt 같은 정식 Issuer 사용
```

확인:

```bash
kubectl get clusterissuer
kubectl get certificate -n university
kubectl get secret university-tls-secret -n university
```

브라우저에서 HTTPS 접속 시 경고가 나면 인증서가 잘못 적용된 것이 아니라, self-signed 인증서를 브라우저가 신뢰하지 않기 때문일 수 있습니다.

### 12-13) Ingress 문제 생길 때 확인 순서

1. ingress-nginx controller Pod가 떠 있는지 확인

```bash
kubectl get pods -n ingress-nginx
```

2. ingress-nginx controller Service가 NodePort로 열렸는지 확인

```bash
kubectl get svc -n ingress-nginx
```

3. Ingress가 적용되었는지 확인

```bash
kubectl get ingress -n university
kubectl describe ingress university-ingress -n university
```

4. backend Service가 존재하는지 확인

```bash
kubectl get svc -n university
```

5. backend Pod가 Ready인지 확인

```bash
kubectl get pod -n university
```

6. Host 라우팅 테스트

```bash
curl -I -H "Host: university.beyond.com" http://localhost:30080
curl -I -H "Host: api.department.beyond.com" http://localhost:30080
```

7. ingress-nginx 로그 확인

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```
