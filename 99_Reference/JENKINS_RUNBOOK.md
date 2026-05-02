# Jenkins CI 실습 정리

목표: GitHub private repository의 BE 프로젝트를 Jenkins에서 checkout하고, Kubernetes agent Pod에서 Maven 빌드 후 Docker 이미지를 빌드/푸시한다. 이후 Manifest Repository의 image tag를 수정해서 Argo CD가 Kubernetes에 자동 배포하도록 만들고, Discord로 CI/CD 결과 알림을 보낸다.

---

## 0) Jenkins 개요

Jenkins는 소프트웨어 개발 과정에서 CI/CD를 자동화하는 오픈 소스 자동화 서버이다.

```text
CI: Continuous Integration
→ 코드를 자주 통합하고, 빌드/테스트를 자동으로 실행하는 것

CD: Continuous Delivery 또는 Continuous Deployment
→ 빌드된 결과물을 배포 가능한 상태로 만들거나, 실제 환경에 자동 배포하는 것
```

Jenkins는 `Pipeline`을 통해 빌드, 테스트, 배포 과정을 코드로 정의할 수 있다. 이 Pipeline 코드는 보통 repository의 `Jenkinsfile`에 저장한다.

주요 기능:

```text
빌드 자동화
→ 소스 코드를 컴파일하고 실행 가능한 산출물 artifact를 만든다.

테스트 자동화
→ 단위 테스트, 통합 테스트 등을 실행해 코드 품질을 확인한다.

배포 자동화
→ 생성된 산출물을 개발, 스테이징, 운영 환경으로 배포한다.

Pipeline
→ 빌드, 테스트, 배포 과정을 단계별 Stage로 관리한다.

플러그인 확장
→ GitHub, Docker, Kubernetes, Discord 등 다양한 도구와 연결할 수 있다.
```

Jenkins는 보통 Controller와 Agent 구조로 동작한다.

```text
Jenkins Controller
→ Jenkins UI, Job 설정, Pipeline 실행 관리 담당

Jenkins Agent
→ 실제 빌드, 테스트, Docker build 같은 작업 수행
```

이번 실습에서는 Jenkins Controller는 Kubernetes의 `jenkins` namespace에 설치했고, 빌드가 실행될 때마다 임시 Kubernetes Agent Pod가 생성되도록 구성했다.

---

## 0-1) Jenkins 설치

Jenkins를 배포할 namespace를 만든다.

```bash
kubectl create namespace jenkins
```

Helm에 Jenkins chart repository를 등록한다.

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
```

Jenkins chart의 기본 values 파일을 가져온다.

```bash
helm show values jenkins/jenkins > jenkins-values.yaml
```

이번 실습에서 중요하게 수정한 값:

```yaml
controller:
  admin:
    createSecret: false

  containerEnv:
    - name: TZ
      value: Asia/Seoul

  javaOpts: "-Duser.timezone=Asia/Seoul"

  serviceType: NodePort
  nodePort: 30020
```

의미:

```text
controller.admin.createSecret: false
→ 초기 관리자 Secret을 Helm이 자동 생성하지 않도록 설정한다.

containerEnv TZ=Asia/Seoul
→ Jenkins 컨테이너의 timezone을 한국 시간으로 맞춘다.

javaOpts: "-Duser.timezone=Asia/Seoul"
→ Jenkins JVM 시간대도 한국 시간으로 맞춘다.

serviceType: NodePort
nodePort: 30020
→ Docker Desktop Kubernetes 밖에서 http://localhost:30020 으로 Jenkins에 접속할 수 있게 한다.
```

수정한 values 파일로 Jenkins를 설치한다.

```bash
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  -f jenkins-values.yaml
```

설치 확인:

```bash
kubectl get all -n jenkins
```

접속:

```text
http://localhost:30020
```

이번 실습에서는 초기 계정을 아래처럼 만들었다.

```text
Username: admin
Password: beyond
```

---

## 0-2) Pipeline 기본 구조

Pipeline은 Jenkins가 실행할 작업 흐름이다. 보통 `Jenkinsfile`에 작성하고, repository에 함께 올려서 CI/CD 과정을 코드로 관리한다.

기본 구조:

```groovy
pipeline {
    agent any

    options {
        // Pipeline 옵션
    }

    environment {
        // 환경 변수
    }

    stages {
        stage('Build') {
            steps {
                // 빌드 작업
            }
        }

        stage('Test') {
            steps {
                // 테스트 작업
            }
        }

        stage('Deploy') {
            steps {
                // 배포 작업
            }
        }
    }

    post {
        always {
            // 성공/실패와 관계없이 항상 실행
        }

        success {
            // 성공했을 때 실행
        }

        failure {
            // 실패했을 때 실행
        }
    }
}
```

이번 실습에서는 `agent any` 대신 Kubernetes Agent를 사용했다.

```text
Pipeline 시작
→ Jenkins가 Kubernetes Agent Pod 생성
→ maven 컨테이너에서 Maven build
→ docker 컨테이너에서 Docker image build/push
→ 빌드 종료 후 Agent Pod 제거
```

---

## 1) 현재 성공한 결과

Discord 알림 예시:

```text
Jenkins
✅ Jenkins Build Success

Job: university-test
Build: #5
Branch: N/A
Image: jin604/department-test:5
Duration: 1 min 19 sec and counting
URL: http://jenkins:8080/job/university-test/5/
```

초기 CI 성공 흐름:

```text
GitHub push
→ ngrok
→ Jenkins /github-webhook/
→ Kubernetes Jenkins agent Pod 생성
→ Maven Build
→ Docker Image Build
→ DockerHub Push
→ Discord 알림
```

현재는 GitOps CD까지 연결했다.

```text
GitHub source push
→ Jenkins Maven Build
→ Docker image build
→ DockerHub push
→ Manifest Repository image tag 수정
→ Manifest Repository commit & push
→ Argo CD가 변경 감지
→ Kubernetes rollout
→ Discord CI/CD 상태 알림
```

Discord 알림은 다음 상태를 나눠서 표시한다.

```text
CI: SUCCESS
Manifest: SUCCESS
CD: SUCCESS
```

---

## 2) Repository 구조

현재 Jenkinsfile은 repo root에 두고, BE는 하위 폴더에서 빌드한다.

```text
university-test/
├── BE_DepartmentService/
│   ├── Dockerfile
│   ├── pom.xml
│   ├── mvnw
│   ├── src/
│   └── target/              # 빌드 결과물. 보통 gitignore 대상
├── FE_university/
├── Jenkinsfile
└── README.md
```

중요:

```text
Jenkinsfile이 root에 있으므로 BE 명령은 dir('BE_DepartmentService') 안에서 실행한다.
Dockerfile 파일명은 대문자 D의 Dockerfile을 권장한다.
```

---

## 3) SSH Key와 GitHub 연동

Jenkins 전용 SSH key 생성:

```bash
ssh-keygen -t ed25519 -C "jenkins for github" -f ~/.ssh/id_ed25519_jenkins
chmod 600 ~/.ssh/id_ed25519_jenkins
chmod 644 ~/.ssh/id_ed25519_jenkins.pub
```

파일 역할:

```text
~/.ssh/id_ed25519_jenkins      → 개인키. Jenkins Credential에 등록
~/.ssh/id_ed25519_jenkins.pub  → 공개키. GitHub Deploy Key에 등록
```

GitHub private repo에 공개키 등록:

```text
GitHub repository
→ Settings
→ Deploy keys
→ Add deploy key
```

읽기만 필요하면 `Allow write access`는 체크하지 않는다.

Jenkins Credential:

```text
Kind: SSH Username with private key
ID: github-jenkins-for-university-test
Username: git
Private Key: ~/.ssh/id_ed25519_jenkins 내용
```

Git URL은 HTTPS가 아니라 SSH 주소를 사용한다.

```text
git@github.com:<owner>/<repo>.git
```

Jenkins에서 GitHub에 처음 SSH로 접속할 때 Host Key 검증 문제가 날 수 있다.

설정 위치:

```text
Jenkins 관리
→ Security
→ Git Host Key Verification Configuration
→ Host Key Verification Strategy
```

이번 실습에서는 아래 옵션을 사용했다.

```text
Accept first connection
```

의미:

```text
Jenkins가 GitHub에 처음 SSH 접속할 때 GitHub 서버의 Host Key를 자동으로 신뢰하고 저장한다.
이후 접속부터는 저장된 Host Key와 비교해서 다른 서버로 바뀌었는지 확인한다.
```

학습/로컬 실습에서는 편하게 쓸 수 있지만, 운영 환경에서는 보안 정책에 맞게 Known hosts file 방식 등을 검토하는 것이 좋다.

---

## 4) Jenkins Credentials

이번 실습에서 사용한 Credentials:

```text
github-jenkins-for-university-test
→ GitHub private repo checkout용 SSH private key

github-jenkins-for-university-test-manifest
→ Manifest Repository push용 SSH private key

dockerhub-access
→ DockerHub push용 username/password 또는 access token

discord-webhook
→ Discord Webhook URL
```

DockerHub Credential:

```text
Kind: Username with password
ID: dockerhub-access
Username: DockerHub username
Password: DockerHub Access Token 권장
```

주의:

```text
DockerHub username과 이미지 namespace가 맞아야 한다.

예:
로그인 계정: jin604
이미지 이름: jin604/department-test
```

Discord Credential:

```text
Kind: Secret text
ID: discord-webhook
Secret: Discord Webhook URL 한 줄
```

주의:

```text
Secret에는 URL만 넣는다.
따옴표, DISCORD_WEBHOOK_URL=, 줄바꿈을 넣지 않는다.
```

Manifest Repository용 Credential:

```text
Kind: SSH Username with private key
ID: github-jenkins-for-university-test-manifest
Username: git
Private Key: manifest repository deploy key의 private key
```

GitHub Manifest Repository에는 해당 public key를 Deploy Key로 등록한다.

```text
GitHub Manifest Repository
→ Settings
→ Deploy keys
→ Add deploy key
→ Allow write access 체크
```

주의:

```text
GitHub Deploy Key는 repository 단위 key다.
같은 public key를 여러 repository의 Deploy Key로 재사용하면 "Key is already in use"가 발생할 수 있다.
Source Repository용 key와 Manifest Repository용 key는 분리하는 것이 좋다.
```

---

## 5) GitHub Webhook

Webhook은 특정 이벤트가 발생했을 때 다른 서버로 즉시 요청을 보내는 방식이다.

이번 실습에서는 GitHub repository에 push가 발생하면 GitHub가 Jenkins로 HTTP 요청을 보내고, Jenkins가 그 요청을 받아 Pipeline Job을 실행한다.

```text
GitHub push
→ GitHub Webhook 발생
→ Jenkins /github-webhook/ 로 요청 전달
→ Jenkins Job 실행
```

Jenkins Job은 빌드, 테스트, 배포 같은 작업을 자동으로 수행하는 실행 단위이다.

이번 실습의 Job 구성:

```text
Item type: Pipeline
Repository: GitHub private repository
Pipeline Definition: Pipeline script from SCM
SCM: Git
Credentials: github-jenkins-for-university-test
Branch Specifier: */main
Script Path: Jenkinsfile
```

Trigger 설정:

```text
Build Triggers
→ GitHub hook trigger for GITScm polling
```

이 옵션을 켜야 GitHub Webhook 요청이 들어왔을 때 Jenkins Job이 자동으로 실행된다.

GitHub Webhook을 사용하려면 Jenkins에 GitHub 관련 플러그인이 필요하다.

```text
Jenkins 관리
→ Plugins
→ Available Plugins
→ GitHub plugin 설치
```

ngrok으로 Jenkins를 외부에 노출했다.

예:

```text
https://defame-equinox-viewer.ngrok-free.dev -> http://localhost:30020/
```

ngrok을 쓰는 이유:

```text
Jenkins는 내 Mac의 Docker Desktop Kubernetes 안에서 localhost:30020으로 떠 있다.
GitHub는 인터넷 밖에 있으므로 내 localhost로 직접 요청할 수 없다.
ngrok이 공개 HTTPS 주소를 만들고, 그 요청을 내 localhost:30020으로 터널링해준다.
```

ngrok 실행:

```bash
ngrok http http://localhost:30020/
```

GitHub Webhook Payload URL은 Jenkins root가 아니라 아래 경로여야 한다.

```text
https://<ngrok-domain>/github-webhook/
```

예:

```text
https://defame-equinox-viewer.ngrok-free.dev/github-webhook/
```

GitHub Webhook 설정:

```text
Payload URL: https://<ngrok-domain>/github-webhook/
Content type: application/json
Events: Just the push event
```

Jenkins Job 설정:

```text
Build Triggers
→ GitHub hook trigger for GITScm polling
```

`/github-webhook/` 경로는 Jenkins GitHub plugin이 Webhook 요청을 받는 고정 endpoint이다.
따라서 GitHub Webhook의 Payload URL에는 반드시 이 경로를 붙인다.

ngrok 로그에서 정상 요청은 아래처럼 보인다.

```text
POST /github-webhook/ 200 OK
```

잘못된 예:

```text
POST / 403 Forbidden
```

이 경우 GitHub webhook URL에 `/github-webhook/`가 빠진 것이다.

---

## 6) Jenkins Agent Pod 구조

Jenkins Kubernetes plugin으로 빌드마다 임시 agent Pod를 만든다.

컨테이너:

```text
maven
→ Maven build 실행

docker
→ docker CLI로 이미지 build/push 실행

kubectl
→ CD 결과 확인용 Kubernetes/Argo CD 조회 실행
```

Docker CLI 컨테이너는 host의 Docker socket을 마운트한다.

```yaml
volumeMounts:
- mountPath: "/var/run/docker.sock"
  name: docker-socket
volumes:
- name: docker-socket
  hostPath:
    path: "/var/run/docker.sock"
```

의미:

```text
docker 컨테이너 안의 docker CLI
→ /var/run/docker.sock
→ host Docker daemon
→ 실제 image build/push 수행
```

최종 agent Pod에는 `kubectl` 컨테이너도 추가했다.

```yaml
- name: kubectl
  image: alpine/k8s:1.34.0
  command:
  - cat
  tty: true
```

이 컨테이너는 Kubernetes에 직접 배포하기 위한 것이 아니라 CD 결과를 확인하기 위한 것이다.

확인하는 내용:

```text
Deployment rollout status
Deployment image tag
Argo CD Application sync status
Argo CD Application health status
```

주의:

```text
bitnami/kubectl:1.34.1
→ 해당 tag가 없어 ImagePullBackOff 발생

bitnami/kubectl:latest + command: cat
→ 이미지 안에 cat 명령이 없어 ContainerCannotRun 발생

alpine/k8s:1.34.0
→ kubectl과 기본 shell 명령이 있어 Jenkins agent container로 사용 가능
```

---

## 7) Maven 의존성 다운로드 위치

Jenkins 로그에서 계속 다운로드되는 것은 Maven 의존성 jar이다.

예:

```text
Downloaded from central: https://repo.maven.apache.org/maven2/...
```

현재 구조에서는 빌드마다 임시 Jenkins agent Pod가 생성된다.

```text
빌드 시작
→ agent Pod 생성
→ Maven 의존성 다운로드
→ Pod 내부 ~/.m2/repository 또는 /root/.m2/repository에 저장
→ 빌드 종료
→ agent Pod 삭제
→ Maven cache도 삭제
```

즉 내 Mac의 `~/.m2`에 쌓이는 것이 아니라, 임시 Pod 안에 잠깐 저장됐다가 사라진다.

매번 다운로드를 줄이려면 Maven cache용 PVC를 붙일 수 있다.

---

## 8) CI-only Jenkinsfile

아래 Jenkinsfile은 DockerHub push까지 담당하던 초기 CI-only 버전이다.
현재 최종 버전은 이 뒤의 GitOps CD 확장 내용을 추가한 형태다.

```groovy
pipeline {
    agent {
        kubernetes {
            yaml '''
            apiVersion: v1
            kind: Pod
            metadata:
              name: jenkins-agent
            spec:
              containers:
              - name: maven
                image: maven:3.9.15-eclipse-temurin-21-alpine
                command:
                - cat
                tty: true
              - name: docker
                image: docker:29.4.1-cli-alpine3.23
                command:
                - cat
                tty: true
                volumeMounts:
                - mountPath: "/var/run/docker.sock"
                  name: docker-socket
              volumes:
              - name: docker-socket
                hostPath:
                  path: "/var/run/docker.sock"
            '''
        }
    }

    environment {
        DOCKER_IMAGE_NAME = "jin604/department-test"
        DOCKER_CREDENTIALS_ID = "dockerhub-access"
        DISCORD_WEBHOOK_CREDENTIALS_ID = "discord-webhook"
    }

    stages {
        // stage('SonarQube Analysis') {
        //     steps {
        //         container('maven') {
        //             withSonarQubeEnv('sonarqube-server') {
        //                 sh """mvn verify sonar:sonar \
        //                     -Dsonar.projectKey='DepartmentService' \
        //                     -Dsonar.projectName='DepartmentService'"""
        //             }
        //         }
        //     }
        // }

        stage('Maven Build') {
            steps {
                container('maven') {
                    dir('BE_DepartmentService') {
                        sh 'pwd'
                        sh 'ls -al'
                        sh 'mvn -v'
                        sh 'mvn package -DskipTests'
                        sh 'ls -al'
                        sh 'ls -al ./target'
                    }
                }
            }
        }

        stage('Docker Image Build & Push') {
            steps {
                container('docker') {
                    dir('BE_DepartmentService') {
                        script {
                            def buildNumber = "${env.BUILD_NUMBER}"

                            sh 'docker logout'

                            withCredentials([usernamePassword(
                                credentialsId: DOCKER_CREDENTIALS_ID,
                                usernameVariable: 'DOCKER_USERNAME',
                                passwordVariable: 'DOCKER_PASSWORD'
                            )]) {
                                sh 'echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin'
                            }

                            withEnv(["DOCKER_IMAGE_VERSION=${buildNumber}"]) {
                                sh 'docker -v'
                                sh 'echo $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION'
                                sh 'docker build --no-cache -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION ./'
                                sh 'docker image inspect $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION'
                                sh 'docker push $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION'
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            withCredentials([string(
                credentialsId: DISCORD_WEBHOOK_CREDENTIALS_ID,
                variable: 'DISCORD_WEBHOOK_URL'
            )]) {
                sh """
                curl -X POST \
                -H 'Content-Type: application/json' \
                --data '{
                    "content": "✅ **Jenkins Build Success**\\n\\n**Job**: ${env.JOB_NAME}\\n**Build**: #${env.BUILD_NUMBER}\\n**Branch**: ${env.BRANCH_NAME ?: "N/A"}\\n**Image**: ${DOCKER_IMAGE_NAME}:${env.BUILD_NUMBER}\\n**Duration**: ${currentBuild.durationString}\\n**URL**: ${env.BUILD_URL}"
                }' \
                "${DISCORD_WEBHOOK_URL}"
                """
            }
        }

        failure {
            withCredentials([string(
                credentialsId: DISCORD_WEBHOOK_CREDENTIALS_ID,
                variable: 'DISCORD_WEBHOOK_URL'
            )]) {
                sh """
                curl -X POST \
                -H 'Content-Type: application/json' \
                --data '{
                    "content": "❌ **Jenkins Build Failed**\\n\\n**Job**: ${env.JOB_NAME}\\n**Build**: #${env.BUILD_NUMBER}\\n**Branch**: ${env.BRANCH_NAME ?: "N/A"}\\n**Stage**: Check Jenkins Console Log\\n**Duration**: ${currentBuild.durationString}\\n**URL**: ${env.BUILD_URL}"
                }' \
                "${DISCORD_WEBHOOK_URL}"
                """
            }
        }
    }
}
```

---

## 9) GitOps CD 확장

CI-only 흐름 뒤에 Manifest Repository update와 CD 검증을 추가했다.

최종 흐름:

```text
Maven Build
→ Docker Image Build & Push
→ Update Manifest Repository
→ Verify CD Deployment
→ Discord CI/CD notification
```

추가한 환경 변수:

```groovy
MANIFEST_REPO_CREDENTIALS_ID = "github-jenkins-for-university-test-manifest"
MANIFEST_REPO_URL = "git@github.com:jin605/university-test-manifest.git"

ARGOCD_APP_NAME = "university-test"
ARGOCD_NAMESPACE = "argocd"
APP_NAMESPACE = "university"
APP_DEPLOYMENT_NAME = "department-api-deploy"
```

상태값은 `environment`에 고정으로 두지 않고 첫 stage에서 초기화한다.

```groovy
stage('Init Status') {
    steps {
        script {
            env.CI_STATUS = "NOT_STARTED"
            env.MANIFEST_STATUS = "NOT_STARTED"
            env.CD_STATUS = "NOT_STARTED"
        }
    }
}
```

DockerHub push가 성공하면 CI 상태를 성공으로 바꾼다.

```groovy
sh 'docker push $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_VERSION'
env.CI_STATUS = "SUCCESS"
```

Manifest Repository update stage:

```groovy
stage('Update Manifest Repository') {
    steps {
        container('docker') {
            withCredentials([sshUserPrivateKey(
                credentialsId: MANIFEST_REPO_CREDENTIALS_ID,
                keyFileVariable: 'SSH_KEY',
                usernameVariable: 'GIT_USERNAME'
            )]) {
                sh '''
                    apk add --no-cache git openssh-client

                    mkdir -p ~/.ssh
                    ssh-keyscan github.com >> ~/.ssh/known_hosts

                    rm -rf university-test-manifest

                    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o UserKnownHostsFile=$HOME/.ssh/known_hosts" \
                    git clone "$MANIFEST_REPO_URL"

                    cd university-test-manifest

                    git config user.name "jenkins"
                    git config user.email "jenkins@local"

                    sed -i "s|image: jin604/department-test:.*|image: jin604/department-test:${BUILD_NUMBER}|g" university-test/department-api-deploy.yaml

                    git add university-test/department-api-deploy.yaml
                    git commit -m "Update department image to ${BUILD_NUMBER}" || echo "No changes to commit"

                    GIT_SSH_COMMAND="ssh -i $SSH_KEY -o UserKnownHostsFile=$HOME/.ssh/known_hosts" \
                    git push origin main
                '''

                script {
                    env.MANIFEST_STATUS = "SUCCESS"
                }
            }
        }
    }
}
```

`git config user.name`과 `git config user.email`은 GitHub 로그인 정보가 아니라 commit author 정보다.

```text
commit author name: jenkins
commit author email: jenkins@local
```

CD 검증 stage:

```groovy
stage('Verify CD Deployment') {
    steps {
        container('kubectl') {
            script {
                env.CD_STATUS = "CHECKING"

                try {
                    def expectedImage = "${DOCKER_IMAGE_NAME}:${env.BUILD_NUMBER}"

                    sh """
                        echo "Expected image: ${expectedImage}"

                        for i in \$(seq 1 30); do
                          CURRENT_IMAGE=\$(kubectl get deploy ${APP_DEPLOYMENT_NAME} \
                            -n ${APP_NAMESPACE} \
                            -o=jsonpath='{.spec.template.spec.containers[0].image}')

                          echo "Current image: \$CURRENT_IMAGE"

                          if [ "\$CURRENT_IMAGE" = "${expectedImage}" ]; then
                            break
                          fi

                          echo "Waiting for Argo CD to apply new image..."
                          sleep 10
                        done

                        kubectl rollout status deployment/${APP_DEPLOYMENT_NAME} \
                          -n ${APP_NAMESPACE} \
                          --timeout=300s

                        CURRENT_IMAGE=\$(kubectl get deploy ${APP_DEPLOYMENT_NAME} \
                          -n ${APP_NAMESPACE} \
                          -o=jsonpath='{.spec.template.spec.containers[0].image}')

                        echo "Current image after rollout: \$CURRENT_IMAGE"

                        if [ "\$CURRENT_IMAGE" != "${expectedImage}" ]; then
                          echo "CD failed: expected ${expectedImage}, but got \$CURRENT_IMAGE"
                          exit 1
                        fi

                        APP_SYNC=\$(kubectl get application ${ARGOCD_APP_NAME} \
                          -n ${ARGOCD_NAMESPACE} \
                          -o=jsonpath='{.status.sync.status}')

                        APP_HEALTH=\$(kubectl get application ${ARGOCD_APP_NAME} \
                          -n ${ARGOCD_NAMESPACE} \
                          -o=jsonpath='{.status.health.status}')

                        echo "Argo CD Sync: \$APP_SYNC"
                        echo "Argo CD Health: \$APP_HEALTH"

                        if [ "\$APP_SYNC" != "Synced" ] || [ "\$APP_HEALTH" != "Healthy" ]; then
                          echo "CD failed: Argo CD is \$APP_SYNC / \$APP_HEALTH"
                          exit 1
                        fi
                    """

                    env.CD_STATUS = "SUCCESS"
                } catch (err) {
                    env.CD_STATUS = "FAILED"
                    throw err
                }
            }
        }
    }
}
```

이 stage는 Argo CD가 Git 변경을 감지하는 시간을 고려해서 최대 5분 정도 Deployment image 변경을 기다린다.

## 10) Jenkins용 Kubernetes RBAC

Jenkins agent는 `jenkins` namespace의 `default` ServiceAccount로 실행된다.

CD 검증을 위해 Jenkins가 필요한 권한:

```text
university namespace:
  - deployments 조회
  - replicasets 조회
  - pods 조회

argocd namespace:
  - applications 조회
```

적용한 RBAC:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-cd-read
  namespace: university
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-cd-read
  namespace: university
subjects:
  - kind: ServiceAccount
    name: default
    namespace: jenkins
roleRef:
  kind: Role
  name: jenkins-cd-read
  apiGroup: rbac.authorization.k8s.io

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-argocd-read
  namespace: argocd
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-argocd-read
  namespace: argocd
subjects:
  - kind: ServiceAccount
    name: default
    namespace: jenkins
roleRef:
  kind: Role
  name: jenkins-argocd-read
  apiGroup: rbac.authorization.k8s.io
```

이 권한은 조회 권한만 준다.
Jenkins가 Kubernetes에 직접 apply/delete하는 권한은 없다.

## 11) Discord CI/CD 알림

성공 알림 예:

```text
✅ CI/CD Success

Job: university-test
Build: #11
CI: SUCCESS
Manifest: SUCCESS
CD: SUCCESS
Image: jin604/department-test:11
Argo CD App: university-test
Namespace: university
```

실패 알림 예:

```text
❌ CI/CD Failed

Job: university-test
Build: #11
CI: SUCCESS
Manifest: SUCCESS
CD: FAILED
Image: jin604/department-test:11
Stage: Check Jenkins Console Log
```

이렇게 나누면 CI는 성공했지만 CD 검증만 실패한 경우도 바로 구분할 수 있다.

## 12) 자주 만난 오류와 원인

### GitHub webhook 403

증상:

```text
ngrok log: POST / 403 Forbidden
```

원인:

```text
GitHub webhook URL이 Jenkins root로 되어 있음
```

해결:

```text
https://<ngrok-domain>/github-webhook/
```

### Docker login unauthorized

증상:

```text
unauthorized: incorrect username or password
```

원인:

```text
DockerHub username/password 또는 access token 오류
```

해결:

```text
Jenkins Credential dockerhub-access 확인
Username은 DockerHub username
Password는 DockerHub Access Token 권장
```

### Docker push insufficient_scope

증상:

```text
push access denied
insufficient_scope: authorization failed
```

원인:

```text
로그인 계정과 image namespace가 다르거나
DockerHub repository가 없거나
토큰에 write 권한이 없음
```

해결:

```text
DOCKER_IMAGE_NAME = "jin604/department-test"
DockerHub에 jin604/department-test repository 존재 확인
Access Token write 권한 확인
```

### Discord webhook URL 오류

증상:

```text
curl: (3) bad range specification in URL
```

원인:

```text
Jenkins Secret text에 URL 외의 값이 들어갔거나
따옴표/줄바꿈/잘못된 문자열이 포함됨
```

해결:

```text
discord-webhook Secret text에는 Discord webhook URL만 한 줄로 저장
```

### sshagent DSL 없음

증상:

```text
java.lang.NoSuchMethodError: No such DSL method 'sshagent'
```

원인:

```text
Jenkins에 SSH Agent Plugin이 없거나 Pipeline step으로 사용할 수 없음
```

해결:

```text
sshagent 대신 withCredentials([sshUserPrivateKey(...)]) 사용
```

### kubectl image pull 실패

증상:

```text
ImagePullBackOff
docker.io/bitnami/kubectl:1.34.1: not found
```

원인:

```text
존재하지 않는 image tag 사용
```

해결:

```yaml
image: alpine/k8s:1.34.0
```

### kubectl container가 바로 종료됨

증상:

```text
exec: "cat": executable file not found in $PATH
```

원인:

```text
kubectl image 안에 cat 명령이 없음
```

해결:

```text
Jenkins agent container로 사용할 수 있는 alpine/k8s image 사용
```

### Jenkins kubectl forbidden

증상:

```text
User "system:serviceaccount:jenkins:default" cannot get resource "deployments"
```

원인:

```text
Jenkins agent Pod의 ServiceAccount에 university namespace 조회 권한이 없음
```

해결:

```text
jenkins namespace의 default ServiceAccount에 Role/RoleBinding으로 read 권한 부여
```

### Argo CD 반영 지연

증상:

```text
Expected image: jin604/department-test:11
Current image: jin604/department-test:10
Waiting for Argo CD to apply new image...
```

원인:

```text
Argo CD가 Git repository를 주기적으로 확인하므로 변경 감지까지 시간이 걸림
```

해결:

```text
Verify CD Deployment stage에서 일정 시간 기다리며 Deployment image를 반복 확인
```

---

## 13) 현재 최종 상태

현재는 CI와 GitOps CD가 모두 연결되어 있다.

```text
Source Repository push
→ Jenkins Maven Build
→ Docker image build
→ DockerHub push
→ Manifest Repository image tag update
→ Manifest Repository commit & push
→ Argo CD sync
→ Kubernetes rollout
→ Discord CI/CD notification
```

Jenkins는 Kubernetes에 직접 배포하지 않는다.

```text
Jenkins
→ manifest repository 수정

Argo CD
→ Kubernetes sync/apply
```

이 구조가 현재 프로젝트의 GitOps 배포 방식이다.
