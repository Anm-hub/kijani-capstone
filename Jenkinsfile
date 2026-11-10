pipeline {
    agent {
        docker {
            // Pin the build node image precisely to match your local environment version
            image 'node:22.22.1-bookworm'
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
        HOME             = "${WORKSPACE}/.jenkins-home"
        NPM_CONFIG_CACHE = "${WORKSPACE}/.npm-cache"
        XDG_CONFIG_HOME  = "${WORKSPACE}/.config"
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
                echo "==== Verifying Script Syntax Layouts ===="
                sh 'bash -n scripts/*.sh'

                echo "==== Evaluating Codebase for Hardcoded Assignments & Secret Leaks ===="
                // Target literal assignments (e.g., = or : followed by quotes with 12+ character strings)
                // Cleanly excludes package-lock and example templates using correct pathspec options
                sh '! git grep -E "(=|:)\\s*[\"\'][A-Za-z0-9_-]{12,}[\"\']" -- . ":(exclude)package-lock.json" ":(exclude)k8s/secret.example.yaml"'

                echo "==== Performing Wrangler Dry-Run Syntax Compilations ===="
                script {
                    def workers = ['receipts', 'processor', 'notifier', 'analytics']
                    for (worker in workers) {
                        sh "./scripts/render-config.sh staging"
                        sh "cd workers/${worker} && npx wrangler deploy --dry-run --config wrangler.generated.toml"
                        sh "./scripts/render-config.sh production"
                        sh "cd workers/${worker} && npx wrangler deploy --dry-run --config wrangler.generated.toml"
                    }
                }
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
                    script {
                        // Capture returned layout parameter map into a script block variable
                        def userInput = input(
                            message: "Promote Serverless Pipeline Stack to Production?",
                            ok: "Approve Production Release Promotion",
                            submitter: "admin,Anm-hub", // Change to match your exact user profile credentials name
                            parameters: [text(name: 'APPROVAL_REASON', description: 'Justification reason text is mandatory.')]
                        )
                        
                        // Defensively extract data out from input variables map layout
                        env.STAGE_APPROVER = userInput.toString().contains("APPROVER=") ? "Handled" : "AuthorizedUser"
                        env.STAGE_REASON = userInput.toString()
                        
                        if (env.STAGE_REASON == null || env.STAGE_REASON.trim() == "") {
                            error("Pipeline Promotion Aborted: Release justification reason cannot be left blank.")
                        }
                        
                        def logContent = "Approver: ${env.STAGE_APPROVER}\nReason: ${env.STAGE_REASON}\nTimestamp: ${new Date().toString()}\n"
                        writeFile file: 'approval.txt', text: logContent
                        archiveArtifacts artifacts: 'approval.txt'
                    }
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
    }
}

