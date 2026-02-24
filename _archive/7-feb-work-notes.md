# GL Setup
- [ ] Add contact in GL component mapping to setup posting for lender and colender split data
- [ ] For posting batch gap 1.2 posting types, instead of adding these posting types, we can use transaction code plus posting type to decide the GL accounts instead of just posting types. Will that help or not?
- [ ] In gap 1.3 write-off transaction, if we create ledgers with posting type loss or waiver or loss on write-off, that will decrease my demand amount outstanding and increase the waived amount. Now, if we decrease the demand amount, I will not be able to show the outstanding of the loan because customer may pay after write-off.

- For GAP 1.4 waiver trunk, waiver expense entry, we can use transaction code to decide the loss expense entry, more like the repayment because in repayment, the bank entry is the transaction, is the payment amount, where transaction has the ledgers and those ledgers decide the paid amount. And if the money is remaining, that goes to excess, there is a ledger with posting excess. So similarly, we can use transaction code waiver to decide the expense or that will not be enough for all the edge cases.

- 1.5 is same as 1.4 conceptually I think

- How bank entry will be posted, bank GL entry will be posted for co-lended, splitted transactions. So let's say if the borrower pays 1 lakh and it goes to 80,000 principal and 20,000 interest, and principal has 80-20 split interest has 50-50 split. So those transactions has also the sub-transactions, shared transactions, and the ledgers. Now, the payment was one with one lakh, but there are three transactions, main transaction and shared transactions. So if lender 1 and 2 both download GL report for their, with their filter, so it should give the GL entry of their portion only, with bank GL entry also.

- Gap 1.6: DISBURSEMENT - Upfront Interest Posting Type Incorrect: Here hold transaction, hold posting type can be used to map the upfront interest on unearned GL account using the GL component mapping.

- For fees, think of multiple scenarios where a front deduction has happened, manually added, and then later on paid. In all these three scenarios, how the posting will be happening and how GL component will be configured.

- If we add transaction in component GL mapping, will that solve our problem to most of it or not?

  

  

Let's analyze these points with the gaps that were listed and update the response of each gaps.

  

  

  

  

——— Partner PR ———

- Remove create_bulk, update_bulk from base viewset and base service
- base service and base visit should handle create update, delete read, activate and deactivate until it has to be overridden by the service & viewset class and those should check the resource meta, whether those actions are available or not because their status and actions and permissions may be available, but action is disabled in resource Meta by admin
- also, add permission. Check for all the actions in base view for activate the activate and for custom actions like approve, reject any any action or any any action you should check corresponding permission using permission enum

  

- Approval service folder has many files. Let's combine other functions or classes into model-specific service classes so that we have only model-specific services.
- PR Comments resolution
- Remove these blocks

- # ============================================================================
- # ACTION ENUMS
- # ============================================================================

-