@vantage_test_login @customer_piedmont
Feature: Vantage test server login smoke

  Scenario: Test server user can open BI Dashboard
    Given I launched the "{{browser}}" browser
    And I enter the Application url "{{target_url}}"
    And I select "{{language_name}}" language
    When I set the value="{{app_username}}" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"
