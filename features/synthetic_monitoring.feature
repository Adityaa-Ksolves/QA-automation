@synthetic_monitoring
Feature: Customer endpoint synthetic monitoring

  @customer_piedmont
  Scenario: Piedmont endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_zito
  Scenario: Zito endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_brctv
  Scenario: BRCTV endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_comporium
  Scenario: Comporium endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_sectv
  Scenario: SECTV endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_secv
  Scenario: SECV endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status

  @customer_wow_trial
  Scenario: WOW trial endpoint is reachable
    Given the configured customer endpoint is available
    When I request the customer endpoint
    Then the endpoint should return an acceptable HTTP status
