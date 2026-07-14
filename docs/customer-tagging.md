# Customer Tagging For Synthetic Monitoring

The daily sanity feature contains multiple customer URLs in the same Scenario Outline Examples table. With customer-specific Jenkins agents, each run must execute only the rows for the customer whose VPN/private network is available from that agent.

Do not run only:

```bash
behave features --tags "@synthetic_monitoring"
```

That can execute all customer rows from one agent.

Use a customer tag with the synthetic monitoring tag:

```bash
behave features --tags "@synthetic_monitoring and @customer_piedmont"
```

## Required Customer Tags

Use these tags:

| Customer Key | Gherkin Tag |
| --- | --- |
| `piedmont` | `@customer_piedmont` |
| `zito` | `@customer_zito` |
| `brctv` | `@customer_brctv` |
| `comporium` | `@customer_comporium` |
| `sectv` | `@customer_sectv` |
| `secv` | `@customer_secv` |
| `wow-trial` | `@customer_wow_trial` |

## Example Pattern

Split each Scenario Outline into customer-tagged Examples blocks.

```gherkin
@synthetic_monitoring
Feature: SyntheticMonitoring

  @tc_1985 @sm_modem_rescan
  Scenario Outline: Verify modem rescan functionality on server - "<Server_name>" at Zone "<Zone>"
    And I enter the Application url "<endpoint>"
    ...

    @customer_piedmont
    Examples: Piedmont
      | endpoint                         | username                   | password  | mac_address  | Server_name | Zone |
      | https://piedmont.nimblethis.net/ | rabil.khanna@openvault.com | encrypted | f8790a95ea05 | Piedmont    | 1    |

    @customer_zito
    Examples: Zito
      | endpoint                          | username                   | password  | mac_address  | Server_name | Zone |
      | https://nimble-web.zitomedia.net/ | rabil.khanna@openvault.com | encrypted | 688f2e774d10 | Zito        | 1    |
```

Repeat this pattern for each Scenario Outline in the feature file.

## Validation

To generate a tagged copy of the feature file:

```bash
./scripts/tag-synthetic-monitoring-feature.py path/to/synthetic_monitoring.feature /tmp/synthetic_monitoring.tagged.feature
```

Review the generated file, then copy the reviewed changes into the real QA automation repository.

Run this before enabling daily fan-out:

```bash
./scripts/validate-customer-tags.sh path/to/synthetic_monitoring.feature
```

The script checks that `@synthetic_monitoring` and all required `@customer_*` tags are present.
