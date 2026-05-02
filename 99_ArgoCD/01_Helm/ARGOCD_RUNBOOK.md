# Argo CD Runbook

이 문서는 현재 프로젝트에서 Argo CD가 맡는 역할과 실제 설정값을 정리한 것이다.

목표는 Argo CD Application이 Manifest Repository를 감시하고, Git에 선언된 Kubernetes manifest를 클러스터에 자동으로 sync하도록 구성하는 것이다. Jenkins가 Manifest Repository의 image tag를 수정하면 Argo CD가 변경을 감지하고 `university` namespace의 애플리케이션을 새 Docker image로 재배포한다.

## Argo CD의 역할

Argo CD는 DockerHub를 직접 감시하지 않는다.

Argo CD가 감시하는 대상은 GitHub의 Manifest Repository다.

```text
Manifest Repository
  |
  | detect Git change
  v
Argo CD
  |
  | sync/apply
  v
Kubernetes
```

DockerHub의 새 이미지를 Kubernetes에 반영하려면 manifest 파일의 image tag가 바뀌어야 한다.

예:

```yaml
image: jin604/department-test:10
```

Jenkins가 다음 빌드에서 manifest를 수정한다.

```yaml
image: jin604/department-test:11
```

Argo CD는 이 Git 변경을 감지하고 Kubernetes에 sync한다.

## 현재 완료된 구성

Argo CD는 Helm으로 설치되어 있다.

현재 `argocd-values.yaml`에서 Argo CD Server는 NodePort로 노출되어 있다.

```yaml
server:
  service:
    type: NodePort
    nodePortHttp: 31080
    nodePortHttps: 31443
```

접속 주소:

```text
https://localhost:31443
```

현재 Application:

```text
Application Name: university-test
Project: default
Sync Policy: Automatic
Prune Resources: enabled
Self Heal: enabled
Status: Synced / Healthy
```

Source:

```text
Repository URL: https://github.com/jin605/university-test-manifest.git
Revision: main
Path: university-test
```

Destination:

```text
Cluster URL: https://kubernetes.default.svc
Namespace: university
```

`https://kubernetes.default.svc`는 Kubernetes 클러스터 내부에서 기본 Kubernetes API Server를 가리키는 주소다.
Argo CD가 같은 클러스터에 배포할 때 사용하는 기본 destination이다.

## 전체 CD 흐름

```text
Jenkins
  |
  | Docker image build/push
  v
DockerHub
  - jin604/department-test:<BUILD_NUMBER>

Jenkins
  |
  | update image tag
  | commit & push
  v
Manifest Repository
  |
  | watched by Argo CD
  v
Argo CD Application
  - university-test
  |
  | sync/apply
  v
Kubernetes Deployment
  - namespace: university
  - deployment: department-api-deploy
  |
  | rollout new Pod
  v
Kubernetes node pulls image from DockerHub
```

## DockerHub Pull 시점

Argo CD가 DockerHub에서 image를 pull하는 것이 아니다.

Argo CD는 Kubernetes manifest를 apply한다.

```text
Argo CD
  -> Deployment image field를 새 tag로 변경
```

그 다음 Kubernetes가 새 Pod를 만들 때 DockerHub에서 image를 pull한다.

```text
Kubernetes
  -> new Pod 생성
  -> node가 DockerHub에서 image pull
```

## 감지 지연

Argo CD는 Git repository를 주기적으로 확인한다.

현재 설정:

```yaml
configs:
  cm:
    timeout.reconciliation: 120s
    timeout.reconciliation.jitter: 60s
```

따라서 Jenkins가 manifest repository에 push한 직후 바로 Kubernetes에 반영되지 않을 수 있다.
1~3분 정도 뒤에 Argo CD가 변경을 감지하고 sync할 수 있다.

Jenkins CD 검증 stage는 이 지연을 고려해서 Deployment image가 새 tag로 바뀔 때까지 기다린다.

## Jenkins와 Argo CD 권한 분리

현재 구조에서 Jenkins는 Kubernetes에 직접 apply하지 않는다.

역할 분리:

| 컴포넌트 | 역할 |
| --- | --- |
| Jenkins | build, DockerHub push, manifest repo image tag 수정 |
| Argo CD | manifest repo 감시, Kubernetes sync/apply |
| Kubernetes | Pod 생성, DockerHub image pull |

Jenkins에는 Kubernetes 조회 권한만 부여했다.

```text
jenkins namespace의 default ServiceAccount
  -> university namespace의 Deployment/Pod 조회
  -> argocd namespace의 Application 조회
```

이 권한은 Jenkins가 CD 결과를 확인하기 위한 read-only 권한이다.
실제 배포 권한은 Argo CD가 가진다.

## Repository가 private인 경우

Manifest Repository가 private이면 Application 생성 전에 repository credential을 먼저 등록해야 한다.

UI 기준:

```text
Settings
  -> Repositories
  -> Connect Repo
```

HTTPS 방식이면 GitHub token을 사용한다.

SSH 방식이면 Argo CD가 사용할 private key를 등록해야 한다.
로컬 Mac의 SSH key를 Argo CD가 자동으로 쓰는 것은 아니다.

권장 권한:

```text
Argo CD -> Manifest Repository read 권한
Jenkins -> Manifest Repository write 권한
```

## Argo CD가 하는 일과 안 하는 일

Argo CD가 하는 일:

```text
Manifest Repository 변경 감지
Kubernetes 현재 상태와 Git 상태 비교
OutOfSync 상태 표시
Automatic Sync
Self Heal 활성화 시 drift 복구
Prune 활성화 시 Git에서 사라진 리소스 삭제
```

Argo CD가 하지 않는 일:

```text
Docker image build
DockerHub push
Manifest Repository image tag 수정
Manifest Repository commit & push
```

이 작업들은 Jenkins가 담당한다.

## 확인 명령어

Application 상태:

```bash
kubectl get application university-test -n argocd
```

Argo CD가 인식한 image 목록:

```bash
kubectl get application university-test -n argocd \
  -o=jsonpath='{.status.summary.images}'; echo
```

Application source 확인:

```bash
kubectl get application university-test -n argocd \
  -o yaml | grep -A20 "source:"
```

Deployment image 확인:

```bash
kubectl get deploy department-api-deploy -n university \
  -o=jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Pod rollout 확인:

```bash
kubectl get pods -n university -w
```

강제 refresh가 필요한 경우:

```bash
kubectl annotate application university-test -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

단, Jenkins가 이 명령을 수행하게 하려면 Argo CD Application에 대한 `patch` 권한이 추가로 필요하다.
현재 구조에서는 Jenkins가 직접 refresh하지 않고 Argo CD의 기본 reconciliation 주기를 기다린다.
