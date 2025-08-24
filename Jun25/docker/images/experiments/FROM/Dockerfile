FROM ubuntu:24.04
LABEL author="khaja"
LABEL project="classroom"
RUN apt update && \
    apt install openjdk-17-jdk -y

ADD https://referenceappslt.s3.ap-south-1.amazonaws.com/spring-petclinic-3.3.0-SNAPSHOT.jar /spring-petclinic-3.3.0-SNAPSHOT.jar
EXPOSE 8080
CMD ["java", "-jar", "/spring-petclinic-3.3.0-SNAPSHOT.jar"]