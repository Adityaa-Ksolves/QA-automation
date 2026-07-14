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

pipeline {
  agent none

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '15'))
  }

  parameters {
    choice(
      name: 'CUSTOMER',
      choices: ['piedmont', 'zito', 'brctv', 'comporium', 'sectv', 'secv', 'wow-trial'],
      description: 'Customer environment to test. The job runs on the matching customer-* Jenkins agent label.'
    )
    string(
      name: 'ENVIRONMENT_URL',
      defaultValue: 'https://piedmont.nimblethis.net/',
      description: 'VPN/private application URL reachable from the selected customer agent.'
    )
    choice(
      name: 'BROWSER',
      choices: ['chrome', 'chromium', 'firefox'],
      description: 'Browser requested by the QA automation.'
    )
    string(
      name: 'TEST_TAGS',
      defaultValue: '@synthetic_monitoring and @customer_piedmont',
      description: 'Behave tag expression. Must include the selected customer tag, for example @customer_piedmont.'
    )
    text(
      name: 'QA_TEST_COMMAND',
      defaultValue: '''behave features --tags "${TEST_TAGS}" -D browser="${BROWSER}" -D endpoint="${TARGET_URL}" --no-capture --no-skipped''',
      description: 'Command that runs the existing Python/Behave sanity script inside the Jenkins agent container.'
    )
  }

  stages {
    stage('Validate Routing') {
      agent { label "${customerLabels[params.CUSTOMER]}" }
      steps {
        script {
          if (!customerLabels.containsKey(params.CUSTOMER)) {
            error "Unknown CUSTOMER '${params.CUSTOMER}'. Add it to customerLabels in Jenkinsfile."
          }
          if (!customerTags.containsKey(params.CUSTOMER)) {
            error "Unknown CUSTOMER '${params.CUSTOMER}'. Add it to customerTags in Jenkinsfile."
          }
          if (!params.ENVIRONMENT_URL?.trim()) {
            error 'ENVIRONMENT_URL is required.'
          }
          if (!params.TEST_TAGS?.contains(customerTags[params.CUSTOMER])) {
            error "TEST_TAGS must include ${customerTags[params.CUSTOMER]} so this job only runs rows for ${params.CUSTOMER}."
          }
          env.CUSTOMER_LABEL = customerLabels[params.CUSTOMER]
          env.CUSTOMER_TAG = customerTags[params.CUSTOMER]
        }
        sh '''
          set -eu
          echo "Customer: ${CUSTOMER}"
          echo "Jenkins node: ${NODE_NAME}"
          echo "Expected label: ${CUSTOMER_LABEL}"
          echo "Expected Behave customer tag: ${CUSTOMER_TAG}"
          echo "Behave tags: ${TEST_TAGS}"
          echo "Target URL: ${ENVIRONMENT_URL}"
        '''
      }
    }

    stage('Connectivity Check') {
      agent { label "${customerLabels[params.CUSTOMER]}" }
      steps {
        sh '''
          set -eu
          ./scripts/connectivity-check.sh "${ENVIRONMENT_URL}"
        '''
      }
      post {
        always {
          echo 'Connectivity check output was printed to the console.'
        }
      }
    }

    stage('Run QA Sanity') {
      agent { label "${customerLabels[params.CUSTOMER]}" }
      environment {
        CUSTOMER = "${params.CUSTOMER}"
        TARGET_URL = "${params.ENVIRONMENT_URL}"
        BROWSER = "${params.BROWSER}"
        TEST_TAGS = "${params.TEST_TAGS}"
        QA_TEST_COMMAND = "${params.QA_TEST_COMMAND}"
      }
      steps {
        sh '''
          set -eu
          ./scripts/run-qa-sanity.sh
        '''
      }
      post {
        always {
          echo 'QA sanity output was printed to the console.'
        }
      }
    }
  }

  post {
    always {
      echo "Build completed for ${params.CUSTOMER} at ${params.ENVIRONMENT_URL}"
    }
  }
}
