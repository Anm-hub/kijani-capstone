pipeline {
    agent {
        docker {
            image 'node:22-bookworm'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
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
        // Workspace boundary adjustments targeting permission scopes
        HOME             = "${WORKSPACE}/.jenkins-home"
        NPM_CONFIG_CACHE = "${WORKSPACE}/.npm-cache"
        XDG_CONFIG_HOME  = "${WORKSPACE}/.config"
        CI               = 'true'
        WRANGLER_SEND_METRICS = 'false'
        
        // Secured secrets pulled safely from Jenkins environment vault parameters
        CLOUDFLARE_API_TOKEN = credentials('cloudflare-api-token')
        CLOUDFLARE_ACCOUNT_ID = credentials('cloudflare-account-id')
        API_KEY_STAGING      = credentials('kk-api-key-staging')
        API_KEY_PRODUCTION   = credentials('kk-api-key-production')
    }

    stages {
        stage('Checkout & Initialize') {
            steps {
                sh 'mkdir -p "${HOME}" "${NPM_CONFIG_CACHE}" "${XDG_CONFIG_HOME}"'
                sh 'npm ci'
            }
        }

        stage('Static Checks') {
            steps {
                echo "==== Performing Script Syntax Evaluations ===="
                sh 'bash -n scripts/*.sh'

                echo "==== Performing Secret Leaks and Pattern Scans ===="
                // Fails pipeline instantly if any raw keys leak into code matrices
                sh '! git grep -iE "api_key|token|secret" -- . "::(exclude)Jenkinsfile" "::(exclude)scripts/"'

                echo "==== Performing Wrangler Deployment Dry-Runs ===="
                sh 'export API_KEY=dummy-key-validation-check; ./scripts/render-config.sh staging'
                sh 'cd workers/receipts && npx wrangler deploy --dry-run --config wrangler.generated.toml'
                sh 'cd workers/analytics && npx wrangler deploy --dry-run --config wrangler.generated.toml'
                
                sh './scripts/render-config.sh production'
                sh 'cd workers/receipts && npx wrangler deploy --dry-run --config wrangler.generated.toml'
                sh 'cd workers/analytics && npx wrangler deploy --dry-run --config wrangler.generated.toml'
            }
        }

        stage('Provision Staging Infrastructure') {
            steps {
                echo "==== Configuring Cloudflare Staging Primitives ===="
                sh './scripts/provision.sh staging'
            }
        }

        stage('Deploy Staging Cluster') {
            environment {
                API_KEY = "${API_KEY_STAGING}"
            }
            steps {
                echo "==== Deploying Four-Function Stack to Staging ===="
                // Syncing secrets cleanly over stdin with masked logging streams enabled
                sh 'set +x; ./scripts/deploy.sh staging'
            }
        }

        stage('Smoke Staging Verification') {
            environment {
                API_KEY = "${API_KEY_STAGING}"
            }
            steps {
                echo "==== Running Automated Integration Suite against Staging ===="
                sh './scripts/smoke-test.sh staging'
            }
        }

        stage('Production Approval Gate') {
            steps {
                echo "==== Halting Pipeline Loop for Human Approval ===="
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Promote Serverless Pipeline Stack to KijaniKiosk Production Infrastructure?",
                          ok: "Approve Production Release Promotion",
                          submitter: "admin", // Replace with your explicit Jenkins username if different
                          submitterParameter: 'APPROVER',
                          parameters: [text(name: 'APPROVAL_REASON', description: 'Justification for release modification bounds is non-negotiable.')]
                }
                // Securely archive auditing statements to artifact files
                script {
                    def logContent = "Approver: ${env.APPROVER}\nReason: ${env.APPROVAL_REASON}\nTimestamp: ${new Date().toString()}\n"
                    writeFile file: 'approval.txt', text: logContent
                    archiveArtifacts artifacts: 'approval.txt'
                }
            }
        }

        stage('Provision Production Infrastructure') {
            steps {
                echo "==== Configuring Cloudflare Production Primitives ===="
                sh './scripts/provision.sh production'
            }
        }

        stage('Deploy Production Cluster') {
            environment {
                API_KEY = "${API_KEY_PRODUCTION}"
            }
            steps {
                echo "==== Deploying Stable Stack Layers to Live Edge ==="
                sh 'set +x; ./scripts/deploy.sh production'
            }
        }

        stage('Smoke Production Verification') {
            environment {
                API_KEY = "${API_KEY_PRODUCTION}"
            }
            steps {
                echo "==== Running Automated Integration Suite against Production ===="
                sh './scripts/smoke-test.sh production'
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        failure {
            echo "Pipeline loop failed. Production deployment safety conditions protected."
        }
    }
}
