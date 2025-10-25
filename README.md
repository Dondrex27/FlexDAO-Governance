# FlexDAO Governance Smart Contract

A comprehensive decentralized autonomous organization (DAO) governance system with flexible proposal types, vote delegation, treasury management, and timelock execution on Stacks blockchain.

## Overview

FlexDAO provides a complete governance framework for decentralized communities, enabling member-driven decision making through proposals and voting. The contract supports multiple proposal types, vote delegation, configurable parameters, and secure treasury management.

## Features

- **Multi-Type Proposals**: Funding, parameter changes, membership modifications, and general proposals
- **Vote Delegation**: Members can delegate voting power to trusted representatives
- **Treasury Management**: Secure on-chain treasury with proposal-based fund distribution
- **Timelock Execution**: Delay between approval and execution for security
- **Configurable Parameters**: Adjustable voting periods, quorum, and thresholds
- **Proposal Deposits**: Anti-spam mechanism requiring deposits to create proposals
- **Comprehensive Voting**: Track individual votes with weights and history
- **State Management**: Clear proposal lifecycle from active to executed

## Proposal Types

### Funding Proposals (Type 0)
Request funds from the DAO treasury for projects, grants, or operations.

### Parameter Change Proposals (Type 1)
Modify DAO governance parameters:
- Voting period duration
- Quorum percentage
- Approval threshold
- Proposal deposit amount
- Timelock duration

### Membership Proposals (Type 2)
Add new members or modify existing member voting power.

### General Proposals (Type 3)
Non-executable proposals for community signaling and discussion.

## Proposal Lifecycle

1. **Active**: Proposal created, voting in progress
2. **Passed**: Voting ended, proposal met quorum and approval threshold
3. **Rejected**: Voting ended, proposal failed to meet requirements
4. **Executed**: Passed proposal executed after timelock
5. **Cancelled**: Proposal cancelled by proposer (if no votes)

## Key Functions

### Member Management

#### `add-member`
```clarity
(add-member (new-member principal) (voting-power uint))
```
Add new DAO member with specified voting power (admin only initially).

#### `delegate-votes`
```clarity
(delegate-votes (delegate principal))
```
Delegate your voting power to another member.

#### `undelegate-votes`
```clarity
(undelegate-votes)
```
Reclaim delegated voting power.

### Proposal Creation

#### `create-proposal`
```clarity
(create-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                 (proposal-type uint) (amount uint) (recipient (optional principal)))
```
Create a new proposal. Requires proposal deposit.

**Parameters:**
- `title`: Proposal title (max 256 characters)
- `description`: Detailed description (max 2048 characters)
- `proposal-type`: 0=funding, 1=parameter, 2=membership, 3=general
- `amount`: Amount for funding proposals (in microSTX)
- `recipient`: Recipient address for funding proposals

#### `create-parameter-change-proposal`
```clarity
(create-parameter-change-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                                  (parameter-name (string-ascii 64)) (new-value uint))
```
Create proposal to change DAO parameter.

**Parameter names:**
- "voting-period"
- "quorum-percentage"
- "approval-threshold"
- "proposal-deposit"
- "timelock-duration"

#### `create-membership-change-proposal`
```clarity
(create-membership-change-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                                   (target-member principal) (new-voting-power uint) (is-addition bool))
```
Propose adding member or changing voting power.

### Voting

#### `cast-vote`
```clarity
(cast-vote (proposal-id uint) (support bool))
```
Vote on active proposal. Uses effective voting power (personal + delegated).

**Requirements:**
- Must be active member
- Cannot have delegated votes
- One vote per proposal
- Must vote before end block

### Proposal Finalization

#### `finalize-proposal`
```clarity
(finalize-proposal (proposal-id uint))
```
Finalize proposal after voting period ends. Calculates pass/fail and initiates timelock if passed.

#### `execute-proposal`
```clarity
(execute-proposal (proposal-id uint))
```
Execute passed proposal after timelock expires.

### Treasury Management

#### `deposit-to-treasury`
```clarity
(deposit-to-treasury (amount uint))
```
Deposit STX to DAO treasury. Anyone can contribute.

### Read-Only Functions

- `get-member`: Retrieve member information
- `get-proposal`: Get proposal details
- `get-vote`: Check how address voted
- `get-voting-power`: Get member's base voting power
- `get-effective-voting-power`: Get total voting power including delegations
- `get-treasury-balance`: Current treasury balance
- `calculate-quorum`: Calculate votes needed for quorum
- `has-proposal-passed`: Check if proposal meets pass criteria

## Usage Examples

### Creating and Executing a Funding Proposal

```clarity
;; 1. Create funding proposal for 5000 STX grant
(contract-call? .flexdao create-proposal
  u"Developer Grant for DeFi Integration"
  u"Fund development of new DeFi integration module over 3 months"
  u0  ;; funding type
  u5000000000  ;; 5000 STX
  (some 'ST1DEVELOPER...))
;; Returns: (ok u0) - proposal ID

;; 2. Members vote (voting period: 7 days)
(contract-call? .flexdao cast-vote u0 true)  ;; Vote yes

;; 3. After voting period, finalize
(contract-call? .flexdao finalize-proposal u0)
;; Enters timelock if passed

;; 4. After timelock (~1 day), execute
(contract-call? .flexdao execute-proposal u0)
;; Transfers 5000 STX to developer
```

### Changing DAO Parameters

```clarity
;; Propose extending voting period to 14 days
(contract-call? .flexdao create-parameter-change-proposal
  u"Extend Voting Period"
  u"Increase voting period from 7 to 14 days for better participation"
  "voting-period"
  u2016)  ;; ~14 days in blocks

;; Members vote and execute as above
```

### Vote Delegation

```clarity
;; Alice delegates to Bob
(contract-call? .flexdao delegate-votes 'ST1BOB...)
;; Bob now votes with Alice's power + his own

;; Alice reclaims delegation
(contract-call? .flexdao undelegate-votes)
```

### Adding New Member

```clarity
;; Create membership proposal
(contract-call? .flexdao create-membership-change-proposal
  u"Add New Core Contributor"
  u"Jane has contributed significantly and should become a member"
  'ST1JANE...
  u100  ;; 100 voting power
  true)  ;; is addition

;; After passing and execution, Jane is a member
```

## Governance Parameters

### Default Values
- **Voting Period**: 1008 blocks (~7 days)
- **Quorum**: 20% of total voting power
- **Approval Threshold**: 51% of votes cast
- **Proposal Deposit**: 1000 STX
- **Timelock Duration**: 144 blocks (~1 day)

### Modifying Parameters
Parameters can be changed through parameter-change proposals approved by members.

## Security Features

1. **Proposal Deposits**: Prevents spam by requiring STX deposit
2. **Timelock Execution**: Delay between approval and execution
3. **Vote Weight Tracking**: Prevents double voting
4. **Delegation Controls**: Cannot vote if votes delegated
5. **State Validation**: Strict state machine for proposals
6. **Treasury Protection**: Only executable through approved proposals

## Voting Power Calculation

**Base Voting Power**: Assigned when member joins
**Delegated Power**: Sum of power delegated by others
**Effective Voting Power**: Base + Delegated

Example:
- Alice: 100 base power
- Bob: 50 base power, delegates to Alice
- Alice's effective power: 150 (can vote with 150 weight)

## Best Practices

### For Proposers
- Write clear, detailed descriptions
- Include implementation timeline
- Specify exact amounts and recipients
- Engage community before formal proposal

### For Members
- Review proposals thoroughly before voting
- Participate in discussion
- Delegate wisely if unable to vote regularly
- Monitor treasury health

### For DAOs
- Set appropriate quorum (not too high)
- Use timelock for security
- Regular parameter reviews
- Transparent treasury management

## Error Codes

- `u300`: Owner-only operation
- `u301`: Proposal/member not found
- `u302`: Unauthorized action
- `u303`: Invalid proposal parameters
- `u304`: Already voted on proposal
- `u305`: Voting period closed
- `u306`: Proposal did not pass
- `u307`: Proposal already executed
- `u308`: Insufficient voting power
- `u309`: Member already exists
- `u310`: Invalid state transition

## Integration Examples

### Frontend Integration
```javascript
// Get proposal details
const proposal = await contract.getProposal(proposalId);

// Calculate if passed
const hasPassed = await contract.hasProposalPassed(proposalId);

// Get user's voting power
const votingPower = await contract.getEffectiveVotingPower(userAddress);

// Vote on proposal
await contract.castVote(proposalId, true);
```

### Multi-Sig Integration
Use FlexDAO alongside multi-sig for dual governance:
- FlexDAO for community decisions
- Multi-sig for emergency actions

## Deployment

```bash
clarinet contract deploy flexdao
```

## Testing

```bash
clarinet test
```

## Future Enhancements

- **Quadratic Voting**: Implement alternative voting mechanisms
- **Sub-DAOs**: Nested governance structures
- **Veto Rights**: Special member privileges
- **Snapshot Voting**: Gas-free off-chain signaling
- **Reputation System**: Dynamic voting power based on participation

## Contributing

Contributions welcome! Please ensure:
- All tests pass
- Documentation updated
- Security considerations addressed

## License

MIT License
