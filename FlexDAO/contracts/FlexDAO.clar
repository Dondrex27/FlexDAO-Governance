;; FlexDAO - Flexible Decentralized Autonomous Organization Governance
;; A comprehensive DAO governance system with proposals, voting, and treasury management

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-unauthorized (err u302))
(define-constant err-invalid-proposal (err u303))
(define-constant err-already-voted (err u304))
(define-constant err-voting-closed (err u305))
(define-constant err-proposal-not-passed (err u306))
(define-constant err-already-executed (err u307))
(define-constant err-insufficient-votes (err u308))
(define-constant err-member-exists (err u309))
(define-constant err-invalid-state (err u310))

;; Proposal states
(define-constant proposal-state-active u0)
(define-constant proposal-state-passed u1)
(define-constant proposal-state-rejected u2)
(define-constant proposal-state-executed u3)
(define-constant proposal-state-cancelled u4)

;; Proposal types
(define-constant proposal-type-funding u0)
(define-constant proposal-type-parameter u1)
(define-constant proposal-type-membership u2)
(define-constant proposal-type-general u3)

;; Data Variables
(define-data-var proposal-nonce uint u0)
(define-data-var voting-period uint u1008) ;; ~7 days in blocks
(define-data-var quorum-percentage uint u2000) ;; 20% (basis points)
(define-data-var approval-threshold uint u5100) ;; 51% (basis points)
(define-data-var proposal-deposit uint u1000000000) ;; 1000 STX
(define-data-var treasury-balance uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var timelock-duration uint u144) ;; ~1 day

;; Member Management
(define-map members
  { address: principal }
  {
    voting-power: uint,
    joined-at: uint,
    delegated-to: (optional principal),
    is-active: bool
  }
)

(define-map delegated-votes
  { delegate: principal }
  { total-delegated-power: uint }
)

;; Proposals
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-utf8 256),
    description: (string-utf8 2048),
    proposal-type: uint,
    amount: uint,
    recipient: (optional principal),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    state: uint,
    executed-at: (optional uint)
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  {
    vote-weight: uint,
    support: bool,
    voted-at: uint
  }
)

(define-map execution-queue
  { proposal-id: uint }
  { execution-ready-at: uint }
)

(define-map parameter-changes
  { proposal-id: uint }
  {
    parameter-name: (string-ascii 64),
    new-value: uint
  }
)

(define-map membership-changes
  { proposal-id: uint }
  {
    target-member: principal,
    new-voting-power: uint,
    is-addition: bool
  }
)

;; Read-only functions
(define-read-only (get-member (address principal))
  (map-get? members { address: address })
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-voting-power (address principal))
  (let
    (
      (member (unwrap! (map-get? members { address: address }) (err u0)))
    )
    (ok (get voting-power member))
  )
)

(define-read-only (get-effective-voting-power (address principal))
  (let
    (
      (member (unwrap! (map-get? members { address: address }) (err u0)))
      (base-power (get voting-power member))
      (delegated-power (default-to { total-delegated-power: u0 } 
                        (map-get? delegated-votes { delegate: address })))
    )
    (ok (+ base-power (get total-delegated-power delegated-power)))
  )
)

(define-read-only (get-treasury-balance)
  (ok (var-get treasury-balance))
)

(define-read-only (calculate-quorum)
  (ok (/ (* (var-get total-voting-power) (var-get quorum-percentage)) u10000))
)

(define-read-only (has-proposal-passed (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u0)))
      (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
      (quorum (unwrap-panic (calculate-quorum)))
      (approval-votes (/ (* total-votes (var-get approval-threshold)) u10000))
    )
    (ok (and 
      (>= total-votes quorum)
      (>= (get yes-votes proposal) approval-votes)
    ))
  )
)

;; Member Management
(define-public (add-member (new-member principal) (voting-power uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> voting-power u0) err-invalid-proposal)
    (asserts! (is-none (map-get? members { address: new-member })) err-member-exists)
    
    (map-set members
      { address: new-member }
      {
        voting-power: voting-power,
        joined-at: stacks-block-height,
        delegated-to: none,
        is-active: true
      }
    )
    
    (var-set total-voting-power (+ (var-get total-voting-power) voting-power))
    (ok true)
  )
)

(define-public (delegate-votes (delegate principal))
  (let
    (
      (member (unwrap! (map-get? members { address: tx-sender }) err-not-found))
      (delegate-member (unwrap! (map-get? members { address: delegate }) err-not-found))
      (voting-power (get voting-power member))
      (current-delegate (get delegated-to member))
    )
    (asserts! (get is-active member) err-unauthorized)
    (asserts! (get is-active delegate-member) err-unauthorized)
    (asserts! (not (is-eq tx-sender delegate)) err-invalid-proposal)
    
    ;; Remove from current delegate if exists
    (match current-delegate
      old-delegate 
        (let
          (
            (old-delegated (default-to { total-delegated-power: u0 } 
                            (map-get? delegated-votes { delegate: old-delegate })))
          )
          (map-set delegated-votes
            { delegate: old-delegate }
            { total-delegated-power: (- (get total-delegated-power old-delegated) voting-power) }
          )
        )
      true
    )
    
    ;; Add to new delegate
    (let
      (
        (new-delegated (default-to { total-delegated-power: u0 } 
                        (map-get? delegated-votes { delegate: delegate })))
      )
      (map-set delegated-votes
        { delegate: delegate }
        { total-delegated-power: (+ (get total-delegated-power new-delegated) voting-power) }
      )
    )
    
    ;; Update member
    (map-set members
      { address: tx-sender }
      (merge member { delegated-to: (some delegate) })
    )
    
    (ok true)
  )
)

(define-public (undelegate-votes)
  (let
    (
      (member (unwrap! (map-get? members { address: tx-sender }) err-not-found))
      (voting-power (get voting-power member))
      (current-delegate (unwrap! (get delegated-to member) err-not-found))
    )
    (let
      (
        (delegated (default-to { total-delegated-power: u0 } 
                    (map-get? delegated-votes { delegate: current-delegate })))
      )
      (map-set delegated-votes
        { delegate: current-delegate }
        { total-delegated-power: (- (get total-delegated-power delegated) voting-power) }
      )
    )
    
    (map-set members
      { address: tx-sender }
      (merge member { delegated-to: none })
    )
    
    (ok true)
  )
)

;; Proposal Creation
(define-public (create-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                                 (proposal-type uint) (amount uint) (recipient (optional principal)))
  (let
    (
      (proposal-id (var-get proposal-nonce))
      (member (unwrap! (map-get? members { address: tx-sender }) err-unauthorized))
      (end-block (+ stacks-block-height (var-get voting-period)))
    )
    (asserts! (get is-active member) err-unauthorized)
    (asserts! (> (get voting-power member) u0) err-insufficient-votes)
    
    ;; Collect proposal deposit
    (try! (stx-transfer? (var-get proposal-deposit) tx-sender (as-contract tx-sender)))
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        amount: amount,
        recipient: recipient,
        start-block: stacks-block-height,
        end-block: end-block,
        yes-votes: u0,
        no-votes: u0,
        state: proposal-state-active,
        executed-at: none
      }
    )
    
    (var-set proposal-nonce (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (create-parameter-change-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                                                   (parameter-name (string-ascii 64)) (new-value uint))
  (let
    (
      (proposal-id (try! (create-proposal title description proposal-type-parameter u0 none)))
    )
    (map-set parameter-changes
      { proposal-id: proposal-id }
      {
        parameter-name: parameter-name,
        new-value: new-value
      }
    )
    (ok proposal-id)
  )
)

(define-public (create-membership-change-proposal (title (string-utf8 256)) (description (string-utf8 2048))
                                                    (target-member principal) (new-voting-power uint) (is-addition bool))
  (let
    (
      (proposal-id (try! (create-proposal title description proposal-type-membership u0 (some target-member))))
    )
    (map-set membership-changes
      { proposal-id: proposal-id }
      {
        target-member: target-member,
        new-voting-power: new-voting-power,
        is-addition: is-addition
      }
    )
    (ok proposal-id)
  )
)

;; Voting
(define-public (cast-vote (proposal-id uint) (support bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) err-not-found))
      (member (unwrap! (map-get? members { address: tx-sender }) err-unauthorized))
      (effective-power (unwrap-panic (get-effective-voting-power tx-sender)))
    )
    (asserts! (get is-active member) err-unauthorized)
    (asserts! (is-eq (get state proposal) proposal-state-active) err-voting-closed)
    (asserts! (<= stacks-block-height (get end-block proposal)) err-voting-closed)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) err-already-voted)
    (asserts! (is-none (get delegated-to member)) err-unauthorized) ;; Cannot vote if delegated
    
    (map-set votes
      { proposal-id: proposal-id, voter: tx-sender }
      {
        vote-weight: effective-power,
        support: support,
        voted-at: stacks-block-height
      }
    )
    
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal {
        yes-votes: (if support (+ (get yes-votes proposal) effective-power) (get yes-votes proposal)),
        no-votes: (if support (get no-votes proposal) (+ (get no-votes proposal) effective-power))
      })
    )
    
    (ok true)
  )
)

;; Proposal Finalization
(define-public (finalize-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) err-not-found))
      (passed (unwrap-panic (has-proposal-passed proposal-id)))
    )
    (asserts! (is-eq (get state proposal) proposal-state-active) err-invalid-state)
    (asserts! (> stacks-block-height (get end-block proposal)) err-voting-closed)
    
    (if passed
      (begin
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { state: proposal-state-passed })
        )
        
        ;; Add to execution queue with timelock
        (map-set execution-queue
          { proposal-id: proposal-id }
          { execution-ready-at: (+ stacks-block-height (var-get timelock-duration)) }
        )
        
        ;; Refund deposit to proposer
        (try! (as-contract (stx-transfer? (var-get proposal-deposit) tx-sender (get proposer proposal))))
        
        (ok true)
      )
      (begin
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { state: proposal-state-rejected })
        )
        (ok false)
      )
    )
  )
)

;; Proposal Execution
(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) err-not-found))
      (queue-data (unwrap! (map-get? execution-queue { proposal-id: proposal-id }) err-not-found))
    )
    (asserts! (is-eq (get state proposal) proposal-state-passed) err-proposal-not-passed)
    (asserts! (>= stacks-block-height (get execution-ready-at queue-data)) err-voting-closed)
    
    ;; Execute based on proposal type
    (if (is-eq (get proposal-type proposal) proposal-type-funding)
      (try! (execute-funding-proposal proposal-id))
      (if (is-eq (get proposal-type proposal) proposal-type-parameter)
        (try! (execute-parameter-proposal proposal-id))
        (if (is-eq (get proposal-type proposal) proposal-type-membership)
          (try! (execute-membership-proposal proposal-id))
          true
        )
      )
    )
    
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal {
        state: proposal-state-executed,
        executed-at: (some stacks-block-height)
      })
    )
    
    (ok true)
  )
)

(define-private (execute-funding-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) err-not-found))
      (amount (get amount proposal))
      (recipient (unwrap! (get recipient proposal) err-invalid-proposal))
    )
    (asserts! (<= amount (var-get treasury-balance)) err-invalid-proposal)
    
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    (ok true)
  )
)

(define-private (execute-parameter-proposal (proposal-id uint))
  (let
    (
      (param-change (unwrap! (map-get? parameter-changes { proposal-id: proposal-id }) err-not-found))
      (param-name (get parameter-name param-change))
      (new-value (get new-value param-change))
    )
    (if (is-eq param-name "voting-period")
      (var-set voting-period new-value)
      (if (is-eq param-name "quorum-percentage")
        (var-set quorum-percentage new-value)
        (if (is-eq param-name "approval-threshold")
          (var-set approval-threshold new-value)
          (if (is-eq param-name "proposal-deposit")
            (var-set proposal-deposit new-value)
            (if (is-eq param-name "timelock-duration")
              (var-set timelock-duration new-value)
              false
            )
          )
        )
      )
    )
    (ok true)
  )
)

(define-private (execute-membership-proposal (proposal-id uint))
  (let
    (
      (membership-change (unwrap! (map-get? membership-changes { proposal-id: proposal-id }) err-not-found))
      (target (get target-member membership-change))
      (new-power (get new-voting-power membership-change))
      (is-addition (get is-addition membership-change))
    )
    (if is-addition
      (begin
        (try! (add-member target new-power))
        (ok true)
      )
      (let
        (
          (member (unwrap! (map-get? members { address: target }) err-not-found))
          (old-power (get voting-power member))
        )
        (map-set members
          { address: target }
          (merge member { voting-power: new-power })
        )
        (var-set total-voting-power (+ (- (var-get total-voting-power) old-power) new-power))
        (ok true)
      )
    )
  )
)

;; Treasury Management
(define-public (deposit-to-treasury (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok true)
  )
)

;; Admin Functions
(define-public (set-voting-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set voting-period new-period)
    (ok true)
  )
)

(define-public (set-quorum (new-quorum uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-quorum u10000) err-invalid-proposal)
    (var-set quorum-percentage new-quorum)
    (ok true)
  )
)