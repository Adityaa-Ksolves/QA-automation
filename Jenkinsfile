def customerLabels = [
  'piedmont': 'customer-piedmont',
  'zito': 'customer-zito',
  'brctv': 'customer-brctv',
  'comporium': 'customer-comporium',
  'sectv': 'customer-sectv',
  'secv': 'customer-secv',
  'wow-trial': 'customer-wow-trial'
]

def customerTags = [
  'piedmont': '@customer_piedmont',
  'zito': '@customer_zito',
  'brctv': '@customer_brctv',
  'comporium': '@customer_comporium',
  'sectv': '@customer_sectv',
  'secv': '@customer_secv',
  'wow-trial': '@customer_wow_trial'
]

def customerUrls = [
  'piedmont': 'https://piedmont.nimblethis.net/',
  'zito': 'https://nimble-web.zitomedia.net/',
  'brctv': 'https://brctv.pnm.openvault.net/',
  'comporium': 'https://comporiumv5.nimblethis.net/',
  'sectv': 'http://sectv.vantage.openvault.net/',
  'secv': 'https://secv.pnm.openvault.net/',
  'wow-trial': 'https://wow-vantage-trial.openvault.net/'
]

pipeline {
  agent { label "${params.RUN_AGENT_LABEL}" }

  options {
    timestamps()
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '15'))
  }

  parameters {
    choice(
      name: 'CUSTOMER',
      choices: ['piedmont', 'zito', 'brctv', 'comporium', 'sectv', 'secv', 'wow-trial'],
      description: 'Customer environment to test. Controls target URL defaults and Behave customer row filtering.'
    )
    string(
      name: 'RUN_AGENT_LABEL',
      defaultValue: 'customer-piedmont',
      description: 'Jenkins node label used to run the test. Use customer-piedmont to test all customers from the Piedmont agent.'
    )
    string(
      name: 'ENVIRONMENT_URL',
      defaultValue: '',
      description: 'Optional application URL override. Leave blank to use the selected customer default URL.'
    )
    choice(
      name: 'BROWSER',
      choices: ['chrome', 'chromium', 'firefox'],
      description: 'Browser requested by the QA automation.'
    )
    string(
      name: 'APP_USERNAME',
      defaultValue: 'rabil.khanna@openvault.com',
      description: 'Application username for parameterized login-smoke tests such as vantage_test_login.feature.'
    )
    string(
      name: 'TEST_TAGS',
      defaultValue: '@synthetic_monitoring and @customer_piedmont',
      description: 'Behave tag expression. Must include the selected customer tag, for example @customer_piedmont.'
    )
    text(
      name: 'QA_TEST_COMMAND',
      defaultValue: '''behave features/ui_synthetic_monitoring.feature --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --format plain --no-source --no-capture --no-skipped --logging-level ERROR --junit --junit-directory artifacts/test-results''',
      description: 'Command that runs the existing Python/Behave sanity script inside the Jenkins agent container.'
    )
    string(
      name: 'QA_PASSWORD_FERNET_CREDENTIALS_ID',
      defaultValue: '',
      description: 'Optional Jenkins Secret text credential ID containing the Fernet key used to decrypt encrypted passwords.'
    )
    string(
      name: 'APP_PASSWORD_CREDENTIALS_ID',
      defaultValue: 'rabil-password',
      description: 'Jenkins Secret text credential ID containing the plain application password. Used when Fernet key is unavailable.'
    )
  }

  stages {
    stage('Validate Routing') {
      steps {
        checkout scm
        script {
          if (!customerLabels.containsKey(params.CUSTOMER)) {
            error "Unknown CUSTOMER '${params.CUSTOMER}'. Add it to customerLabels in Jenkinsfile."
          }
          if (!customerTags.containsKey(params.CUSTOMER)) {
            error "Unknown CUSTOMER '${params.CUSTOMER}'. Add it to customerTags in Jenkinsfile."
          }
          if (!customerUrls.containsKey(params.CUSTOMER)) {
            error "Unknown CUSTOMER '${params.CUSTOMER}'. Add it to customerUrls in Jenkinsfile."
          }
          if (!params.RUN_AGENT_LABEL?.trim()) {
            error 'RUN_AGENT_LABEL is required.'
          }
          if (!params.TEST_TAGS?.contains(customerTags[params.CUSTOMER])) {
            error "TEST_TAGS must include ${customerTags[params.CUSTOMER]} so this job only runs rows for ${params.CUSTOMER}."
          }
          env.RESOLVED_ENVIRONMENT_URL = params.ENVIRONMENT_URL?.trim() ? params.ENVIRONMENT_URL.trim() : customerUrls[params.CUSTOMER]
          env.CUSTOMER_LABEL = customerLabels[params.CUSTOMER]
          env.CUSTOMER_TAG = customerTags[params.CUSTOMER]
        }
        sh '''
          set +x
          set -eu
          echo "Customer: ${CUSTOMER}"
          echo "Jenkins node: ${NODE_NAME}"
          echo "Run agent label: ${RUN_AGENT_LABEL}"
          echo "Customer default label: ${CUSTOMER_LABEL}"
          echo "Expected Behave customer tag: ${CUSTOMER_TAG}"
          echo "Behave tags: ${TEST_TAGS}"
          echo "Target URL: ${RESOLVED_ENVIRONMENT_URL}"
          if [ -n "${APP_USERNAME:-}" ]; then echo "App username: ${APP_USERNAME}"; fi
        '''
      }
    }

    stage('Connectivity Check') {
      steps {
        sh '''
          set +x
          set -eu
          ./scripts/connectivity-check.sh "${RESOLVED_ENVIRONMENT_URL}"
        '''
      }
      post {
        always {
          echo 'Connectivity check output was printed to the console.'
        }
      }
    }

    stage('Run QA Sanity') {
      environment {
        CUSTOMER = "${params.CUSTOMER}"
        BROWSER = "${params.BROWSER}"
        APP_USERNAME = "${params.APP_USERNAME}"
        TEST_TAGS = "${params.TEST_TAGS}"
        QA_TEST_COMMAND = "${params.QA_TEST_COMMAND}"
      }
      steps {
        script {
          def credentialsToBind = []
          if (params.APP_PASSWORD_CREDENTIALS_ID?.trim()) {
            credentialsToBind.add(string(
              credentialsId: params.APP_PASSWORD_CREDENTIALS_ID,
              variable: 'APP_PASSWORD'
            ))
          }
          if (params.QA_PASSWORD_FERNET_CREDENTIALS_ID?.trim()) {
            credentialsToBind.add(string(
              credentialsId: params.QA_PASSWORD_FERNET_CREDENTIALS_ID,
              variable: 'QA_PASSWORD_FERNET_KEY'
            ))
          }

          withEnv(["TARGET_URL=${env.RESOLVED_ENVIRONMENT_URL}", "ENVIRONMENT_URL=${env.RESOLVED_ENVIRONMENT_URL}"]) {
            if (credentialsToBind) {
              withCredentials(credentialsToBind) {
                sh '''
                  set +x
                  set -eu
                  ./scripts/run-qa-sanity.sh
                '''
              }
            } else {
              sh '''
                set -eu
                ./scripts/run-qa-sanity.sh
              '''
            }
          }
        }
      }
      post {
        always {
          junit testResults: 'artifacts/test-results/*.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'artifacts/**/*', allowEmptyArchive: true
          echo 'QA sanity output was printed to the console.'
        }
      }
    }
  }

  post {
    always {
      echo "Build completed for ${params.CUSTOMER} at ${env.RESOLVED_ENVIRONMENT_URL}"
    }
  }
}
