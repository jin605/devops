FROM eclipse-temurin:21-jre-alpine-3.22
LABEL maintainer="hong123 <hong123@beyond.com>"
LABEL version="1.0"
# 이미지의 /root 디렉터리에 department-service-0.0.1-SNAPSHOT.jar 파일 복사
COPY department-service-0.0.1-SNAPSHOT.jar /root
# docker build 명령어 실행 시 Dockerfile 내부로 값을 전달을 수 있는 변수 선언 (기본값 dev)
ARG BUILD_PROFILE=dev
# docker build 명령어 실행 시 Dockerfile 내부로 값을 전달을 수 있는 변수 선언 (기본값 8088)
ARG BUILD_PORT=8088
# Timezone 환경변수를 Asia/Seoul로 설정
ENV TZ=Asia/Seoul
# BUILD_PROFILE 변수의 값으로 APP_PROFILE 환경변수의 값을 설정
ENV APP_PROFILE=${BUILD_PROFILE}
# BUILD_PORT 변수의 값으로 이미지에서 노출할 포트를 설정
EXPOSE ${BUILD_PORT}
# 작업 디렉터리를 /root로 변경
WORKDIR /root
# 컨테이너 실행 시 university-0.0.1-SNAPSHOT.jar 파일을 실행하도록 설정
CMD ["java", "-jar", "department-service-0.0.1-SNAPSHOT.jar", "--spring.profiles.active=${APP_PROFILE}"]