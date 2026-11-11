pipeline {
    agent {
        docker {
            // Pinned runtime build node image
            image 'node:22.22.1-bookworm'
        }
    }

    options {
        timeout(time: 1, unit: 'HOURS')
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        HOME             = "${WORKSPACE}/.jenkins-home"
        NPM_CONFIG_CACHE = "${WORKSPACE}/.npm-cache"
        XDG_CONFIG_HOME  = "${WORKSPACE}/.config"
        STAGE            = 'staging'
        CI               = 'true'
        WRANGLER_SEND_METRICS = 'false'
        
        CLOUDFLARE_API_TOKEN  = credentials('cloudflare-api-token')
        CLOUDFLARE_ACCOUNT_ID = credentials('cloudflare-account-id')
        API_KEY_STAGING       = credentials('kk-api-key-staging')
        API_KEY_PRODUCTION    = credentials('kk-api-key-production')
    }

    stages {
        stage('Checkout & Initialize') {
            steps {
                sh 'mkdir -p "${HOME}" "${NPM_CONFIG_CACHE}" "${XDG_CONFIG_HOME}"'
                sh 'npm ci'
            }
        }

        stage('Static & Secret Checks') {
            steps {
                echo "==== Performing Script Syntax Evaluations ===="
                sh 'bash -n scripts/*.sh'

                echo "==== Invoking Independent Secret Scanner Script ===="
                sh './scripts/secret-scan.sh'

                echo "==== Performing Wrangler Dry-Run Compilations ===="
                // Compiles configuration matrices once per environment lifecycle segment
                sh './scripts/render-config.sh staging'
                script {
                    def workers = ['receipts', 'processor', 'notifier', 'analytics']
                    for (w in workers) {
                        sh "cd workers/${w} && npx wrangler deploy --dry-run --config wrangler.generated.toml"
                    }
                }
                
                sh './scripts/render-config.sh production'
                script {
                    def workers = ['receipts', 'processor', 'notifier', 'analytics']
                    for (w in workers) {
                        sh "cd workers/${w} && npx wrangler deploy --dry-run --config wrangler.generated.toml"
                    }
                }
            }
        }

        stage('Provision Staging Infrastructure') {
            steps {
                sh './scripts/provision.sh staging'
            }
        }

        stage('Deploy Staging Cluster') {
            environment {
                API_KEY = "${API_KEY_STAGING}"
            }
            steps {
                sh 'set +x; ./scripts/render-config.sh staging; ./scripts/deploy.sh staging'
            }
        }

        stage('Smoke Staging Verification') {
            environment {
                API_KEY = "${API_KEY_STAGING}"
            }
            steps {
                sh './scripts/smoke-test.sh staging'
            }
        }

        stage('Production Approval Gate') {
            steps {
                echo "==== Halting Pipeline Loop for Human Approval ===="
                timeout(time: 30, unit: 'MINUTES') {
                    script {
                        // Capture returned layout parameter map into a script block variable
                        // Replace 'Anm-hub' with your explicit, case-sensitive Jenkins username
                        def userInput = input(
                            message: "Promote Serverless Pipeline Stack to Production?",
                            ok: "Approve Production Release Promotion",
                            submitter: "Anm-hub",
                            submitterParameter: 'APPROVER',
                            parameters: [text(name: 'APPROVAL_REASON', description: 'Release justification reason is non-negotiable.')]
                        )
                        
                        String rawReason = userInput['APPROVAL_REASON']
                        String rawApprover = userInput['APPROVER']
                        
                        if (rawReason == null || rawReason.trim() == "") {
                            error("Pipeline Promotion Aborted: Release justification reason cannot be left blank.")
                        }
                        
                        def logContent = "Approver: ${rawApprover}\nReason: ${rawReason.trim()}\nTimestamp: ${new Date().toString()}\n"
                        writeFile file: 'approval.txt', text: logContent
                        archiveArtifacts artifacts: 'approval.txt'
                    }
                }
            }
        }

        stage('Provision Production Infrastructure') {
            steps {
                sh './scripts/provision.sh production'
            }
        }

        stage('Deploy Production Cluster') {
            environment {
                API_KEY = "${API_KEY_PRODUCTION}"
            }
            steps {
                sh 'set +x; ./scripts/render-config.sh production; ./scripts/deploy.sh production'
            }
        }

        stage('Smoke Production Verification') {
            environment {
                API_KEY = "${API_KEY_PRODUCTION}"
            }
            steps {
                sh './scripts/smoke-test.sh production'
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}

