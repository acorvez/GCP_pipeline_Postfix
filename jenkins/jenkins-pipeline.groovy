pipeline {
    agent any
    
    environment {
        GITLAB_CREDS = credentials('gitlab-credentials')
        DOCKER_REGISTRY = 'localhost:5000'
        IMAGE_NAME = 'postfix-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout([$class: 'GitSCM', 
                    branches: [[name: '*/main']], 
                    doGenerateSubmoduleConfigurations: false, 
                    extensions: [], 
                    submoduleCfg: [], 
                    userRemoteConfigs: [[
                        credentialsId: 'gitlab-credentials', 
                        url: 'http://gitlab.example.com/gitops/postfix-app.git'
                    ]]
                ])
            }
        }
        
        stage('Build') {
            steps {
                sh 'docker-compose -f docker-compose.yml build'
            }
        }
        
        stage('Test') {
            steps {
                sh 'docker-compose -f docker-compose.yml -f docker-compose.test.yml up --exit-code-from test'
            }
        }
        
        stage('Push Docker Image') {
            steps {
                sh "docker tag postfix-app:latest ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                sh "docker tag postfix-app:latest ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
                sh "docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                sh "docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
            }
        }
        
        stage('Deploy to Development') {
            steps {
                sh """
                sed -i 's|image: postfix-app:latest|image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}|g' docker-compose.yml
                scp docker-compose.yml admin@postfix:/opt/postfix/
                ssh admin@postfix 'cd /opt/postfix && docker-compose up -d'
                """
            }
        }
        
        stage('Verify Deployment') {
            steps {
                sh "sleep 10" // Wait for services to start
                sh "curl -f http://postfix:8080/health || exit 1"
            }
        }
    }
    
    post {
        success {
            echo 'Pipeline completed successfully!'
            // Notify stakeholders about successful deployment
            slackSend channel: '#deployments', 
                      color: 'good', 
                      message: "Deployment Successful: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        }
        failure {
            echo 'Pipeline failed!'
            // Notify stakeholders about failed deployment
            slackSend channel: '#deployments', 
                      color: 'danger', 
                      message: "Deployment Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            
            // Rollback if needed
            sh """
            ssh admin@postfix 'cd /opt/postfix && docker-compose stop && docker-compose pull && docker-compose up -d'
            """
        }
        always {
            // Clean workspace
            cleanWs()
        }
    }
}
