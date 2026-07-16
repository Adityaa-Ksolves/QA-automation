@synthetic_monitoring @customer_piedmont @customer_zito @customer_brctv @customer_comporium @customer_sectv @customer_secv @customer_wow_trial
Feature: SyntheticMonitoring

  Background: Launch application
    Given I launched the "{{browser}}" browser

  @tc_1985 @sm_modem_rescan
  Scenario Outline: Verify modem rescan functionality on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    And I select "{{language_name}}" language
    When I set the value="<username>" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"

    And I enter the Application url "<endpoint>/modem-details/<mac_address>"
    Then I will wait till all the loader icons disappears from the screen
    And I capture the "text" for the webelement having xpath="//span[contains(text(),'Latest Poll Time')]/.." and store it in "session.polltime_before"
    And I click on "Rescan Modem" having xpath="//button[.//span[contains(normalize-space(),'Rescan Modem')]]"
    Then I will wait till all the loader icons disappears from the screen
    And I will wait till the "dialog box" having "text=Rescanning Modem" disappears from the screen within 150 seconds
    And I wait for 3 seconds
    And I capture the "text" for the webelement having xpath="//span[contains(text(),'Latest Poll Time')]/.." and store it in "session.polltime_after"
    And I make sure that "{{session.polltime_before}}" "not equals" "{{session.polltime_after}}"

    Examples:
      | endpoint                                 | username                   | password                                                                                             | mac_address       | Server_name | Zone |
      | https://piedmont.nimblethis.net/         | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | f8790a95ea05      | Piedmont    | 1    |
      | https://nimble-web.zitomedia.net/        | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 688f2e774d10      | Zito        | 1    |
      | https://brctv.pnm.openvault.net/         | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 20f19e135ac4      | BRCTV       | 1    |
      | https://comporiumv5.nimblethis.net/      | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | acdb4819b195      | Comporium   | 1    |
      | http://sectv.vantage.openvault.net/      | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 70:DF:F7:19:82:FF | Sectv       | 1    |
      | https://secv.pnm.openvault.net/          | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 28:80:88:AD:33:E0 | Secv        | 1    |
      | https://wow-vantage-trial.openvault.net/ | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 80:CC:9C:04:B1:68 | Wow-trial   | 1    |

  @tc_1986 @sm_fbc_modem_install
  Scenario Outline: Verify that user is able to install modem and generate a birth certificate for a FBC detected modem on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    And I select "{{language_name}}" language
    When I set the value="<username>" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"

    When I select "Install CM" from the hamburger menu
    And I set the value="<mac_address>" for "macid>>textbox" having "data-placeholder=Mac Address"
    And I click on "install_modem>>button" having "text=Install Modem"
    And I will wait till the "label" having "text~Installing Modem" disappears from the screen within 180 seconds
    And I make sure that "label" having "text~Modem Detected" is visible to me on the "Modem Detected Dialog Box"
    And I make sure that "button" having "text:=Get Certificate" is visible to me on the "Modem Detected Dialog Box"
    And I make sure that "button" having "text:=Get Spectra" is visible to me on the "Modem Detected Dialog Box"
    And I click on "button" having "text:=Get Spectra"
    And I will wait till the "label" having "text~Requesting" disappears from the screen within 150 seconds
    And I will wait till the "label" having "text~Getting Spectra Data" disappears from the screen within 150 seconds
    And I click on "button" having "text:=Get Certificate"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "macid>>label" having "text:=<mac_address>" is visible to me on the "certificate details section"
    And I make sure that "view_birth_certificate>>button" having "text=View Birth Certificate" is visible to me on the "certificate details section"

    Examples:
      | endpoint                            | username                   | password                                                                                             | mac_address       | Server_name | Zone |
      | https://piedmont.nimblethis.net/    | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 44:15:24:01:39:80 | Piedmont    | 1    |
      | https://nimble-web.zitomedia.net/   | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | F8:79:0A:1D:3D:55 | Zito        | 1    |
      | https://comporiumv5.nimblethis.net/ | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | C8:63:FC:3F:35:71 | Comporium   | 1    |

  @tc_1987 @sm_rxmer_modem_install
  Scenario Outline: Verify that user is able to install modem and generate a birth certificate for a RxMER detected modem on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    And I select "{{language_name}}" language
    When I set the value="<username>" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"

    When I select "Install CM" from the hamburger menu
    And I set the value="<mac_address>" for "macid>>textbox" having "data-placeholder=Mac Address"
    And I click on "install_modem>>button" having "text=Install Modem"
    And I will wait till the "label" having "text~Installing Modem" disappears from the screen within 120 seconds
    And I make sure that "label" having "text~Modem Detected" is visible to me on the "Modem Detected Dialog Box"
    And I make sure that "button" having "text:=Get Certificate" is visible to me on the "Modem Detected Dialog Box"
    And I make sure that "button" having "text:=Get RxMER" is visible to me on the "Modem Detected Dialog Box"
    And I click on "button" having "text:=Get RxMER"
    And I will wait till the "label" having "text~Requesting" disappears from the screen within 150 seconds
    And I will wait till the "label" having "text~Get RxMER Data" disappears from the screen within 150 seconds
    And I make sure that "macid>>label" having "text:=<mac_address>" is visible to me on the "certificate details section"
    And I make sure that "view_birth_certificate>>button" having "text=View Birth Certificate" is visible to me on the "certificate details section"

    Examples:
      | endpoint                            | username                   | password                                                                                             | mac_address       | Server_name | Zone |
      | https://nimble-web.zitomedia.net/   | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | F8:79:0A:78:FB:B5 | Zito        | 1    |
      | https://comporiumv5.nimblethis.net/ | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | C8:63:FC:3F:35:71 | Comporium   | 1    |

  @tc_1988 @sm_spectra_modem_rescan
  Scenario Outline: Verify that user is able to do Spectra modem rescan on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    And I select "{{language_name}}" language
    When I set the value="<username>" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"

    And I enter the Application url "<endpoint>/modem-details/<mac_address>"
    Then I will wait till all the loader icons disappears from the screen
    And I click on "label" having "text()=Subscriber Info"
    And I make sure that "button" is "visible" to me on the "home page" having xpath="//mat-panel-title[normalize-space(text())='Spectra Chart']"
    And I click on "panel" having xpath="//mat-expansion-panel-header[.//mat-panel-title[normalize-space(text())='Spectra Chart']]"
    And I will wait till all the loader icons disappears from the screen
    And I press "PAGE_DOWN" key
    And I wait for 1 seconds
    And I capture the "text" for the webelement having xpath="(//mat-expansion-panel[.//mat-panel-title[normalize-space(text())='Spectra Chart']]//*[self::td or self::div or self::span][contains(@class, 'mat-column-display_poll_time') or contains(@class, 'cdk-column-display_poll_time') or contains(@class, 'mat-column-poll_time') or contains(@class, 'cdk-column-poll_time') or contains(@class, 'display_poll_time')])[1]" and store it in "session.polltime_before"
    And I click on "Rescan Spectra" having xpath="(//mat-expansion-panel[.//mat-panel-title[normalize-space(text())='Spectra Chart']]//*[self::button or @role='button'][contains(translate(normalize-space(.), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'rescan')])[1]"
    And I will wait till all the loader icons disappears from the screen
    And I will wait till the "dialog box" having "text=Rescanning spectra" disappears from the screen within 120 seconds
    Then I will wait till all the loader icons disappears from the screen
    And I wait up to 90 seconds for the text of xpath="(//mat-expansion-panel[.//mat-panel-title[normalize-space(text())='Spectra Chart']]//*[self::td or self::div or self::span][contains(@class, 'mat-column-display_poll_time') or contains(@class, 'cdk-column-display_poll_time') or contains(@class, 'mat-column-poll_time') or contains(@class, 'cdk-column-poll_time') or contains(@class, 'display_poll_time')])[1]" to differ from "session.polltime_before" and store it in "session.polltime_after"

    Examples:
      | endpoint                                 | username                   | password                                                                                             | mac_address       | Server_name | Zone |
      | https://piedmont.nimblethis.net/         | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | D4:0A:A9:55:0A:AD | Piedmont    | 1    |
      | https://nimble-web.zitomedia.net/        | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | F8:79:0A:78:FB:B5 | Zito        | 1    |
      | https://brctv.pnm.openvault.net/         | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 3C:2D:9E:45:84:E9 | BRCTV       | 1    |
      | https://comporiumv5.nimblethis.net/      | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 14:C0:3E:B7:1A:39 | Comporium   | 1    |
      | http://sectv.vantage.openvault.net/      | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 14:C0:3E:08:A7:65 | Sectv       | 1    |
      | https://wow-vantage-trial.openvault.net/ | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 08:7E:64:CB:43:73 | Wow-trial   | 1    |

  @tc_1989 @sm_rxmer_modem_rescan
  Scenario Outline: Verify that user is able to do RxMER modem rescan on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    And I select "{{language_name}}" language
    When I set the value="<username>" for "username>>textbox" having "data-placeholder=Enter your username"
    And I click on "continue" having xpath="//span[contains(text(), 'Continue')]"
    And I set the Jenkins password for "password>>textbox" having xpath="//input[@data-placeholder='Enter your password']"
    And I click on "login>>button" having "type=submit and text=login"
    Then I will wait till all the loader icons disappears from the screen
    And I make sure that "title" having "class=title and text()=BI Dashboard" is visible to me on the "home page"

    And I enter the Application url "<endpoint>/modem-details/<mac_address>"
    Then I will wait till all the loader icons disappears from the screen
    And I click on "label" having "text()=Subscriber Info"
    And I make sure that "button" is "visible" to me on the "home page" having xpath="//mat-expansion-panel-header[.//mat-panel-title[contains(normalize-space(), 'RxMER Chart')]]"
    And I click on "panel" having "text=RxMER Chart"
    And I will wait till all the loader icons disappears from the screen
    And I press "PAGE_DOWN" key
    And I press "PAGE_DOWN" key
    And I press "PAGE_DOWN" key
    And I wait for 1 seconds
    And I click on "button#1" having "text():=Rescan"
    And I will wait till all the loader icons disappears from the screen
    And I will wait till the "dialog box" having "text=Rescanning rxmer" disappears from the screen within 120 seconds
    Then I will wait till all the loader icons disappears from the screen
    Then I make sure that "RxMER Data (dB)" is "visible" to me on the "RxMER Chart" having xpath="//*[text()='RxMER Data (dB)']"

    Examples:
      | endpoint                                 | username                   | password                                                                                             | mac_address       | Server_name | Zone |
      | https://nimble-web.zitomedia.net/        | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 74:9B:E8:41:5C:00 | Zito        | 1    |
      | https://brctv.pnm.openvault.net/         | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | 94:6A:77:70:CE:CA | BRCTV       | 1    |
      | https://comporiumv5.nimblethis.net/      | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | acdb48b76a01      | Comporium   | 1    |
      | https://wow-vantage-trial.openvault.net/ | rabil.khanna@openvault.com | gAAAAABp8KlgGnmuryxXBtS6iEAgJXK43ipw_6ME0K6fASAiFrHD6hW-rkqozML6a8q2W3Gz-pb9JP75yYTkgXVhrk7_Q4D_eA== | E0:46:EE:8F:B1:7B | Wow-trial   | 1    |
