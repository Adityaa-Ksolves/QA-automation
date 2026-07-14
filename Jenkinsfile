def customerLabels = [
  'piedmont': 'customer-piedmont',
  'zito': 'customer-zito',
  'brctv': 'customer-brctv',
  'comporium': 'customer-comporium',
  'sectv': 'customer-sectv',
  'secv': 'customer-secv',
  'wow-trial': 'customer-wow-trial'
]

pipeline {
  agent none

  options {
    timestamps()
    ansiColor('xterm')
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
      defaultValue: '@synthetic_monitoring',
      description: 'Optional test tags or filters passed to the QA automation.'
    )
    string(
      name: 'QA_TEST_COMMAND',
      defaultValue: '',
      description: 'Command that runs the existing QA sanity script. If blank, the wrapper fails with setup guidance.'
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
          if (!params.ENVIRONMENT_URL?.trim()) {
            error 'ENVIRONMENT_URL is required.'
          }
          env.CUSTOMER_LABEL = customerLabels[params.CUSTOMER]
        }
        sh '''
          set -eu
          echo "Customer: ${CUSTOMER}"
          echo "Jenkins node: ${NODE_NAME}"
          echo "Expected label: ${CUSTOMER_LABEL}"
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
          archiveArtifacts artifacts: 'artifacts/connectivity/**', allowEmptyArchive: true
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
          junit testResults: 'artifacts/test-results/**/*.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'artifacts/**', allowEmptyArchive: true, fingerprint: true
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
