# CI/CD Runbook

이 문서는 현재 구성한 전체 CI/CD + GitOps CD 흐름을 정리한 것이다.

목표는 개발자가 Source Repository에 push하면 Jenkins가 애플리케이션을 빌드하고 Docker image를 DockerHub에 push한 뒤, Manifest Repository의 image tag를 갱신하도록 만드는 것이다. 이후 Argo CD가 Manifest Repository 변경을 감지해서 Kubernetes에 sync하고, 최종 배포 상태를 Discord 알림으로 확인한다.

## 최종 상태

현재 흐름은 끝까지 연결되었다.

```text
Source Repo push
  -> Jenkins CI 실행
  -> Maven build
  -> Docker image build
  -> DockerHub push
  -> Manifest Repo image tag 수정
  -> Manifest Repo commit & push
  -> Argo CD가 변경 감지
  -> Kubernetes sync/rollout
  -> Discord로 CI/CD 결과 알림
```

확인된 배포 예시:

```text
Docker image: jin604/department-test:11
Argo CD App: university-test
Status: Synced / Healthy
Kubernetes Deployment image: jin604/department-test:11
```

## 전체 흐름

```text
Developer
  |
  | commit & push
  v
GitHub Source Repository
  |
  | webhook
  v
Jenkins
  - UI: http://localhost:30020
  - GitHub webhook endpoint: <ngrok-url>/github-webhook/
  |
  | Maven build
  | Docker image build
  | DockerHub login
  | Docker image push
  v
DockerHub
  - image: jin604/department-test:<BUILD_NUMBER>

Jenkins
  |
  | clone manifest repository
  | update image tag
  | commit & push
  v
GitHub Manifest Repository
  - repo: https://github.com/jin605/university-test-manifest.git
  - path: university-test
  |
  | watched by Argo CD
  v
Argo CD
  - App: university-test
  - UI HTTPS: https://localhost:31443
  - UI HTTP: http://localhost:31080
  |
  | sync/apply
  v
Kubernetes
  - namespace: university
  - deployment: department-api-deploy
  |
  | new Pod rollout
  | node pulls image from DockerHub
  v
Updated Application
```

## DockerHub Pull 시점

Argo CD는 DockerHub에서 이미지를 pull하지 않는다.

역할은 다음처럼 나뉜다.

| 대상 | 역할 |
| --- | --- |
| Jenkins | 이미지를 빌드해서 DockerHub에 push |
| Jenkins | manifest repository의 image tag 수정 |
| Argo CD | manifest repository 변경 감지 후 Kubernetes에 sync |
| Kubernetes | 새 Pod를 만들 때 DockerHub에서 image pull |

즉 DockerHub pull은 다음 순간에 일어난다.

```text
Deployment image tag 변경
  -> ReplicaSet 갱신
  -> 새 Pod 생성
  -> Kubernetes node가 DockerHub에서 새 image pull
```

## 포트와 접속 주소

| 대상 | 접속 주소 | 포트 | 용도 |
| --- | --- | --- | --- |
| Jenkins | `http://localhost:30020` | `30020` | Jenkins UI 접속 |
| Argo CD HTTPS | `https://localhost:31443` | `31443` | Argo CD UI 접속 |
| Argo CD HTTP | `http://localhost:31080` | `31080` | Argo CD HTTP NodePort |
| Ingress HTTP | `http://university.beyond.com:30080` | `30080` | 애플리케이션 HTTP 진입점 |
| Ingress HTTPS | `https://university.beyond.com:30443` | `30443` | 애플리케이션 HTTPS 진입점 |
| API Ingress HTTPS | `https://api.department.beyond.com:30443` | `30443` | Department API HTTPS 진입점 |

로컬 도메인을 사용하려면 `/etc/hosts`에 다음 매핑이 필요하다.

```text
127.0.0.1 university.beyond.com
127.0.0.1 api.department.beyond.com
```

## 주요 Repository

| Repository | 역할 |
| --- | --- |
| `jin605/university-test` | 애플리케이션 source repository, Jenkinsfile 포함 |
| `jin605/university-test-manifest` | Kubernetes manifest repository, Argo CD가 감시 |

Manifest repository 구조:

```text
university-test-manifest/
└── university-test/
    ├── namespace.yaml
    ├── mariadb-*.yaml
    ├── redis-*.yaml
    ├── department-api-deploy.yaml
    ├── department-api-service.yaml
    ├── university-vue-*.yaml
    └── university-ingress.yaml
```

Jenkins가 수정하는 파일:

```text
university-test/department-api-deploy.yaml
```

수정되는 값:

```yaml
image: jin604/department-test:<BUILD_NUMBER>
```

## Jenkins 상태 알림

Discord 알림은 CI/CD 상태를 나눠서 보여준다.

```text
CI: SUCCESS
Manifest: SUCCESS
CD: SUCCESS
```

실패 시 예:

```text
CI: SUCCESS
Manifest: SUCCESS
CD: FAILED
```

의미:

| 상태 | 의미 |
| --- | --- |
| CI | Maven build, Docker build, DockerHub push 성공 여부 |
| Manifest | Manifest repository image tag 수정 및 push 성공 여부 |
| CD | Argo CD sync 후 Kubernetes Deployment image 변경 확인 여부 |

## Argo CD 감지 지연

Argo CD는 Git repository를 실시간으로 계속 당겨보는 것이 아니라 주기적으로 확인한다.

현재 설정:

```yaml
timeout.reconciliation: 120s
timeout.reconciliation.jitter: 60s
```

따라서 Jenkins가 manifest repository에 push한 뒤 Kubernetes에 반영되기까지 1~3분 정도 걸릴 수 있다.

Jenkins의 `Verify CD Deployment` stage는 이 시간을 고려해서 Kubernetes Deployment image가 새 tag로 바뀔 때까지 기다린다.

## 확인 명령어

Argo CD Application 상태:

```bash
kubectl get application university-test -n argocd
```

Argo CD가 인식한 이미지:

```bash
kubectl get application university-test -n argocd \
  -o=jsonpath='{.status.summary.images}'; echo
```

Kubernetes Deployment 이미지:

```bash
kubectl get deploy department-api-deploy -n university \
  -o=jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Pod rollout 확인:

```bash
kubectl get pods -n university -w
```

## 최종 목표 달성 여부

완료된 흐름:

```text
source push
  -> Jenkins build
  -> DockerHub image push
  -> manifest image tag update
  -> manifest repo push
  -> Argo CD sync
  -> Kubernetes rollout
  -> Discord CI/CD notification
```

현재 구조에서 Jenkins는 Kubernetes에 직접 배포하지 않는다.
Jenkins는 manifest repository만 수정하고, 실제 apply/sync는 Argo CD가 담당한다.
