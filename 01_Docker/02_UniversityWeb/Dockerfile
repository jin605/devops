# 베이스 이미지를 eclipse-temurin:21-jre-alpine-3.22로 지정
FROM eclipse-temurin:21-jre-alpine-3.22
LABEL maintainer="hong123 <hong123@beyond.com>"
LABEL version="2.0"
# 이미지의 /root 디렉터리에 university-0.0.1-SNAPSHOT.jar 파일 복사
COPY university-0.0.1-SNAPSHOT.jar /root
# Timezone 환경변수를 Asia/Seoul로 설정
ENV TZ=Asia/Seoul
# SPRING_PROFILES_ACTIVE 환경변수를 live 설정
ENV SPRING_PROFILES_ACTIVE=live
# 이미지에서 8080 포트를 노출
# EXPOSE 8080
EXPOSE 8089
# 작업 디렉터리를 /root로 변경
WORKDIR /root
# 컨테이너 실행 시 university-0.0.1-SNAPSHOT.jar 파일을 실행하도록 설정
CMD [ "java", "-jar", "university-0.0.1-SNAPSHOT.jar" ]
