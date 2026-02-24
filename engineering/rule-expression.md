# Rule Expression

Author: Abhishek Sharma
Status: Outdated
Category: PRD
Last edited time: December 4, 2025 1:25 PM

# Introduction

---

The service helps you evaluate data on customised rules. A rule expression is a JSON data in fixed format. A rule expression will return true or false. Below is the rule expression JSON. 

Rule expression can be built on various data points such as borrower KYC information, demographic data, credit bureau data, banking data, or any additional data you collect.

This JSON contains following keys:

1. `rules` key which can contain one or more fields or another rules key. 
2. `combinator` can be either `and` or `or` which tells what operation should be applied among fields on “rules” key
3. `not` tells whether to take `not`. it can be either true or false
4. `reason` key defines the reason which is used when the `rules` key returns false. 

```json
{
  "rules": [
		{Field 1},
    {
      "rules": [
        {Field 1},
        {Field 2}
      ],
      "combinator": "or",
      "not": false,
    }
  ],
  "combinator": "and",
  "not": false,
	"reason": "Bureau Rejection"
}
```

# Field Schema

---

```json
{
    "key": "defines the path 'eg. applicant.age' from where to pick value from data object",
    "label": "used for showing name of the field in frontend",
    "type": "type of field",
    "operators": ["used for performing type of operation"],
    "options": ["drop down option for select/multi-select"],
		"value_suffix": "used for frontend only",
		"reason": "This failed because of this",
		"data_existence_check": "pass/raise/fail if key is not provided in data",
		"filters": "array of filters used for banking and bureau fields only"
}
```

# Field types

---

## Select

```json
{
    "key": "",
    "label": "",
    "type": "select",
    "options": ["a", "b", "c", "d", "e"],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": "a"
		}
}
```

## Multi-select

```json
{
    "key": "",
    "label": "",
    "type": "multi-select",
    "options": ["a", "b", "c", "d", "e"],
    "operators": ["in", "nin"],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": ["a", "b"],
			"operator": "in"
		}
}
```

## String

```json
{
    "key": "",
    "label": "",
    "type": "string",
    "operators": ["starts-with", "ends-with", "contains", "exact-match", "regex", "not-contains"],
		"output": {
			"value": "abh",
			"operator": "starts-with"
		}
}
```

## Number

```json
{
    "key": "",
    "label": "",
    "type": "number",
    "operators": ["=", ">", ">=", "<", "<=", "!="],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": 4,
			"operator": "="
		}
}
```

## Boolean

```json
{
    "key": "",
    "label": "",
    "type": "boolean",
    "options": ["true", "false"],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": "true"
		}
}
```

## Period (*used for Bureau & Banking)

```json
{
    "key": "",
    "label": "",
    "type": "period",
    "operators": ["=", ">", ">=", "<", "<=", "!="],
    "period_types": ["days", "months", "years"],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": 4,
			"operator": "=",
			"period_type": "months",
			"field_name": "date_open/date_close" // Only for Bureau account/dpds
		}
}
```

## Vintage (*used for Bureau)

```json
{
    "key": "",
    "label": "",
    "type": "vintage",
    "operators": ["=", ">", ">=", "<", "<=", "!="],
    "period_types": ["days", "months", "years"],
		"value_suffix": "",
		"filters": [],
		"output": {
			"value": 4,
			"operator": ">",
			"period_type": "months"
		}
}
```

For evaluation of rule expression, we have to provide “data” and “expression” key.

1. data consist of all the values with keys required for evaluation
2. expression is the JSON which will be used for evaluation

# Possible Fields

---

## Applicant

- Gender
    
    ```json
    {
        "key": "applicant.gender",
        "label": "Gender",
        "type": "multi_select",
        "options": ["male", "female", "others"],
        "operators": ["in", "nin"],
    }
    ```
    
- Age
    
    ```json
    {
        "key": "applicant.age",
        "label": "Age",
        "type": "number",
        "operators": [">", ">=", "<", "<="]
    }
    ```
    
- Current Address Ownership
    
    ```json
    {
        "key": "applicant.current_address_ownership",
        "label": "Current Address Ownership",
        "type": "multi_select",
        "options": ["rented", "owned"],
        "operators": ["in", "nin"],
    }
    ```
    

## Business

- Business Type
    
    ```json
    {
        "key": "business.business_type",
        "label": "Business",
        "type": "multi_select",
        "operators": ["in", "nin"],
    		"options": ["proprietorship", "llp", "partnership", "private_limited", "limited", "individual"]
    }
    ```
    
- Business Vintage
    
    ```json
    {
        "key": "business.overall_vintage",
        "label": "Overall Business Vintage",
        "type": "number",
        "operators": [">", ">=", "<", "<="],
        "value_suffix": "months"
    }
    ```
    
- Business Vintage with Partner
    
    ```json
    {
        "key": "business.vintage_with_partner_in_months",
        "label": "Vintage with Partner",
        "type": "number",
        "operators": [">", ">=", "<", "<="],
        "value_suffix": "months"
    }
    ```
    
- Current Address Ownership
    
    ```json
    {
        "key": "business.current_address_ownership",
        "label": "Current Address Ownership",
        "type": "multi_select",
        "options": ["rented", "owned"],
        "operators": ["in", "nin"],
    }
    ```
    

## Extra Fields as per Lead Data Config

<aside>
🎊 Extra fields works similar to applicant and business

</aside>

- Example
    
    ```json
    {
        "key": "business.brand",
        "label": "Brand",
        "type": "multi_select",
        "options": ["apple", "samsung", "nothing"],
        "operators": ["in", "nin"],
    }
    ```
    

## Verification Matrix Fields

- Business Authenticity Check
    
    ```json
    {
        "key": "matrix_data.business_authenticity",
        "label": "Business Authenticity",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_authenticity.name_match",
        "label": "Business Name Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_authenticity.business_type_match",
        "label": "Business Type Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_authenticity.address_match",
        "label": "Business Address Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_authenticity.incorporation_year_match",
        "label": "Business Incorporation Year Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
- Business Person Check
    
    ```json
    {
        "key": "matrix_data.business_person_check",
        "label": "Business Person Check",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_person_check.name_match",
        "label": "Business Person Name Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.business_person_check.gst_pan_link_match",
        "label": "Business GST PAN Link",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
- Person Authenticity Check
    
    ```json
    {
        "key": "matrix_data.person_authenticity",
        "label": "Person Authenticity",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.person_authenticity.name_match",
        "label": "Person Name Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.person_authenticity.father_name_match",
        "label": "Person's Father Name Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.person_authenticity.address_match",
        "label": "Person Address Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
    ```json
    {
        "key": "matrix_data.person_authenticity.dob_match",
        "label": "Person DOB Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    
- Bank Check
    
    ```json
    {
        "key": "matrix_data.bank_account_authenticity.name_match",
        "label": "Bank Name Match",
        "type": "multi_select",
        "options": ["R", "Y", "G"],
        "operators": ["in", "nin"]
    }
    ```
    

## Bureau

- Score
    
    ```json
    {
        "key": "{applicant_type}.bureau-score", //applicant_type can be business or applicant
        "label": "Bureau Score",
        "type": "number",
        "operators": ["=", ">", ">=", "<", "<="]
    }
    ```
    
- Accounts
    
    ```json
    {
        "key": "{applicant_type}.bureau-accounts", //applicant_type can be business or applicant
        "label": "Loan Accounts",
        "type": "number",
        "operators": ["=", ">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "Period",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
    				{
                "key": "account_date",
                "label": "Account Date",
                "type": "select",
                "choices": ["date_open", "date_close"]
            },
    				{
                "key": "report_date",
                "label": "Report Date",
                "type": "select",
                "choices": ["reported_date", "current_date"]
            },
    				{
                "key": "vintage",
                "label": "with vintage",
                "type": "vintage",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "product_types",
                "label": "Product Types",
                "type": "multi_select",
                "operators": ["in", "nin"],
                "choices": [// pick from Bureau project]
            },
            {
                "key": "aggregation",
                "label": "Aggregation",
                "type": "select",
                "choices": ["sum", "average", "max", "min"],
                "is_required": true
            },
            {
                "key": "field_name",
                "label": "Field Name",
                "type": "select",
                "choices": ["outstanding_amount", "overdue_amount", "sanctioned_amount", "loan_count"],
                "is_required": true
            }
        ]
    }
    ```
    
- Enquiries
    
    ```json
    {
        "key": "{applicant_type}.bureau-enquiries",//applicant_type can be business or applicant
        "label": "Enquiries",
        "type": "number",
        "operators": ["=", ">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "in last",
                "type": "period",
    				    "operators": ["=", ">", ">=", "<", "<=", "!="],
                "period_types": ["months", "years"]
            },
    				{
                "key": "report_date",
                "label": "Report Date",
                "type": "select",
                "choices": ["reported_date", "current_date"]
            },
            {
                "key": "product_types",
                "label": "Product Types",
                "type": "multi_select",
                "operators": ["in", "nin"],
                "choices": [// pick from Bureau project]
            }
        ]
    }
    ```
    
- DPD
    
    ```json
    {
        "key": "{applicant_type}.bureau-dpds", //applicant_type can be business or applicant
        "label": "DPDs",
        "type": "number",
        "operators": ["=", ">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "Period",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
    				{
                "key": "account_date",
                "label": "Account Date",
                "type": "select",
                "choices": ["date_open", "date_close"]
            },
    				{
                "key": "report_date",
                "label": "Report Date",
                "type": "select",
                "choices": ["reported_date", "current_date"]
            },
    				{
                "key": "vintage",
                "label": "with vintage",
                "type": "vintage",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "product_types",
                "label": "Product Types",
                "type": "multi_select",
                "operators": ["in", "nin"],
                "choices": [// pick from Bureau project]
            },
    				{
                "key": "sanctioned_amount",
                "label": "Sanctioned Amount",
                "type": "number",
                "operators": ["=", ">", ">=", "<", "<=", "!="],
    						"value_suffix": ""
            },
           {
                "key": "aggregation",
                "label": "Aggregation",
                "type": "select",
                "choices": ["max", "min"],
                "is_required": true
            }
              
        ]
    }
    ```
    
- Default Account Count
    
    

## Banking

- Credits
    
    ```json
    {
        "key": "{applicant_type}.banking-credits", //applicant_type can be business or applicant
        "label": "Bank Credits",
        "type": "number",
        "operators": [">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "in last",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "aggregation",
                "label": "Aggregation",
                "type": "select",
                "choices": ["sum", "average", "max", "min"]
            }
        ]
    }
    ```
    
- Debits
    
    ```json
    {
        "key": "{applicant_type}.banking-debits",
        "label": "Bank Debits",
        "type": "number",
        "operators": [">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "in last",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "aggregation",
                "label": "Aggregation",
                "type": "select",
                "choices": ["sum", "average", "max", "min"]
            }
        ]
    }
    ```
    
- Bounces
    
    ```json
    {
        "key": "{applicant_type}.banking-bounces",
        "label": "Bank Bounces",
        "type": "number",
        "operators": [">", ">=", "<", "<="],
        "filters": [
    
            {
                "key": "period",
                "label": "in last",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "mode_type",
                "label": "Mode Type",
                "type": "multi_select",
                "operators": ["in", "nin"],
                "choices": ["cheque", "ach"]
            }
        ]
    }
    ```
    
- ABB
    
    ```json
    {
        "key": "{applicant_type}.banking-abb",
        "label": "Bank ABB",
        "type": "number",
        "operators": ["=", ">", ">=", "<", "<="],
        "filters": [
            {
                "key": "period",
                "label": "in last",
                "type": "period",
    				    "operators": [">", ">=", "<", "<="],
                "period_types": ["months", "years"]
            },
            {
                "key": "aggregation",
                "label": "Aggregation",
                "type": "select",
                "choices": ["average", "max", "min"]
            },
            {
                "key": "field_name",
                "label": "Field Name",
                "type": "select",
                "choices": ["daily_average", "weekly_average"]
            }
        ]
    }
    ```
    

# Models

---

There are three types of models 

## Go/No-go

It returns either True or False

```json
{
  "rules": [
		{Field 1},
    {
      "rules": [
        {Field 1},
        {Field 2}
      ],
      "combinator": "or",
      "not": false,
    }
  ],
  "combinator": "and",
  "not": false,
	"reason": "Bureau Rejection"
}
```

- e.g.
    
    ```json
    {
        "rules": [
            {
                "rules": [
                    {
                        "key": "overall_vintage",
                        "type": "number",
                        "output": {
                            "value": 5,
                            "operator": "<"
                        }
                    },
                    {
                        "key": "age",
                        "type": "number",
                        "output": {
                            "value": 40,
                            "operator": ">"
                        }
                    }
                ],
                "combinator": "and"
            },
            {
                "rules": [
                    {
                        "key": "bureau-accounts",
                        "type": "number",
                        "output": {
                            "value": 500000,
                            "operator": "<"
                        },
                        "filters": [
                            {
                                "key": "period",
                                "type": "period",
                                "output": {
                                    "value": "5",
                                    "operator": "<",
                                    "period_type": "months"
                                }
                            },
                            {
                                "key": "aggregation",
                                "type": "select",
                                "is_required": true,
                                "output": {
                                    "value": "sum"
                                }
                            },
                            {
                                "key": "field_name",
                                "type": "select",
                                "is_required": true,
                                "output": {
                                    "value": "outstanding_amount"
                                }
                            }
                        ]
                    },
                    {
                        "key": "residence_address_ownership",
                        "type": "multi_select",
                        "output": {
                            "value": ["rented"],
                            "operator": "in"
                        }
                    }
                ],
                "combinator": "or",
                "not": false
            }
        ],
        "combinator": "and",
        "not": false
    }
    ```
    

## Routing

It combines more than 1 rules and return label as output.

With every rule block there are `fail` and `pass` key which defines the action should be taken on event. Following are the possible combination

- if action is break, output should be choosen
- if action is continue, engine will check for next available rule block for evaluation

```json
[
  {
    "expression": {
      "rules": [
        {Rule OBJECT 1},
        {
          "rules": [
            {Rule OBJECT 1},
            {Rule OBJECT 2}
          ],
          "combinator": "or",
          "not": false,
        }
      ],
      "combinator": "and",
      "not": false,
      "reason": "Bureau Rejection"
    },
    "fail": {
		    "action": "continue/break",
		    "output_type": "program/text",
		    "output": "500"
		},
    "pass": {
		    "action": "continue/break",
		    "output_type": "program/text",
		    "output": "500"
		}
  },
  {
    "expression": {
      "rules": [
        {Rule OBJECT 1},
        {
          "rules": [
            {Rule OBJECT 1},
            {Rule OBJECT 2}
          ],
          "combinator": "or",
          "not": false,
        }
      ],
      "combinator": "and",
      "not": false,
      "reason": "Bureau Rejection"
    },
    "fail": {
		    "action": "continue/break",
		    "output_type": "program/text",
		    "output": "500"
		},
    "pass": {
		    "action": "continue/break",
		    "output_type": "program/text",
		    "output": "500"
		}
  }
]
```

- e.g.
    
    ```json
    {
        "expression": {
    			"rules": [
            {
              "rules": [
                  {
                      "key": "overall_vintage",
                      "type": "number",
                      "output": {
                          "value": 5,
                          "operator": "<"
                      }
                  },
                  {
                      "key": "age",
                      "type": "number",
                      "output": {
                          "value": 40,
                          "operator": ">"
                      }
                  }
              ],
              "combinator": "and"
    	    ],
    	    "combinator": "and",
    	    "not": false
    		},
    		"fail": {
    		    "action": "continue"
    		},
        "pass": {
    		    "action": "break",
    		    "output_type": "text",
    		    "output": "500"
    		}
      }
    }
    ```
    

## Scoring

In this model, engine returns a score depending on given rule expression. Field or group block may have a `score` key with `+` or `-` float value.

**Calculation logic**

- If group has `scoring_rule: field`
    - Field score should be added/subtracted if field evaluates `True`
- If group has `scoring_rule: group`
    - If group evaluates to True then it’s score will be considered else ignored
    - No field should have a score inside group block

```json
{
    "expression": {
      "rules": [
        {Rule OBJECT 1, "score": +20},
        {Rule OBJECT 1, "score": +20},
        {Rule OBJECT 1, "score": +20},
        {
          "rules": [
            {Rule OBJECT 1},
            {Rule OBJECT 2}
          ],
          "combinator": "or",
          "not": false,
		      "scoring_rule": "group",
					"score": +90
        }
      ],
      "combinator": "and",
      "not": false,
      "scoring_rule": "field",
    }
  }
```