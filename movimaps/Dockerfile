# Dockerfile

# === 1. Compilacion ===
FROM eclipse-temurin:21-jdk-alpine-3.21 AS builder

WORKDIR /app

# Copy wrapper from maven & file of config POM
COPY .mvn/ .mvn
COPY mvnw pom.xml ./

# Download dependencies for save in Docker cache
RUN ./mvnw dependency:go-offline -B

# Copy source code & compile JAR skipping test for now
COPY src ./src
RUN ./mvnw clean package -DskipTests



# === 2. Ejecucion ===
FROM eclipse-temurin:21-jre-alpine-3.21

RUN addgroup -S spring && adduser -S spring -G spring

WORKDIR /app

RUN mkdir /recordings && chown spring:spring /recordings
# Copy the compiled JAR file from the previous stage
COPY --from=builder --chown=spring:spring /app/target/movimaps-api.jar app.jar

USER spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
