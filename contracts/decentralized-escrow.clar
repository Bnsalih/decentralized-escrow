;; Decentralized Escrow contract
;; - Escrows are stored by an ID (uint)
;; - The contract holds funds using (as-contract) during escrow
;; - Amounts are in micro-STX (1 STX = 1_000_000 micro-STX)

(define-constant contract-title "Decentralized Escrow")
(define-constant contract-description "Escrow contract with buyer, seller, arbiter roles. Supports deposit, release, refund and cancellation.")

;; Escrow statuses
(define-constant STATUS_PENDING u0)
(define-constant STATUS_FUNDED u1)
(define-constant STATUS_RELEASED u2)
(define-constant STATUS_REFUNDED u3)
(define-constant STATUS_CANCELLED u4)

;; Error codes
(define-constant ERR_NOT_BUYER u100)
(define-constant ERR_NOT_SELLER u101)
(define-constant ERR_NOT_ARBITER u102)
(define-constant ERR_ALREADY_EXISTS u103)
(define-constant ERR_NOT_FOUND u104)
(define-constant ERR_INVALID_AMOUNT u105)
(define-constant ERR_TRANSFER_FAILED u106)
(define-constant ERR_NOT_FUNDED u107)
(define-constant ERR_ALREADY_FUNDED u108)
(define-constant ERR_INVALID_STATUS u109)
(define-constant ERR_DEADLINE_NOT_REACHED u110)
(define-constant ERR_DEADLINE_PASSED u111)
(define-constant ERR_NOT_AUTHORIZED u112)

;; Escrow structure:
;; key: { id: uint }
;; value: { buyer: principal, seller: principal, arbiter: principal,
;;          amount: uint, deposited: bool, status: uint, deadline: uint }
(define-map escrows
  { id: uint }
  {
    buyer: principal,
    seller: principal,
    arbiter: principal,
    amount: uint,
    deposited: bool,
    status: uint,
    deadline: uint
  }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-only: get escrow by id
(define-read-only (get-escrow (id uint))
  (map-get? escrows {id: id})
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Create an escrow
;; - id: unique escrow id
;; - seller: principal
;; - arbiter: principal
;; - amount: uint (micro-STX)
;; - deadline: uint (block-height when escrow expires for auto-refund option)
(define-public (create-escrow (id uint) (seller principal) (arbiter principal) (amount uint) (deadline uint))
  (begin
    ;; basic validation
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    (asserts! (not (is-eq seller tx-sender)) (err ERR_NOT_SELLER))
    (asserts! (not (is-eq arbiter tx-sender)) (err ERR_NOT_ARBITER))
    (asserts! (>= (stx-get-balance tx-sender) amount) (err ERR_INVALID_AMOUNT))
    (match (map-get? escrows {id: id})
      entry (err ERR_ALREADY_EXISTS)
      (let ((buyer tx-sender))
        (map-set escrows {id: id}
                 {
                   buyer: buyer,
                   seller: seller,
                   arbiter: arbiter,
                   amount: amount,
                   deposited: false,
                   status: STATUS_PENDING,
                   deadline: deadline
                 })
        (ok id)
      ))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Deposit funds into an escrow (buyer only)
;; - This will transfer `amount` from tx-sender to the contract (as-contract)
(define-public (deposit (id uint))
  (begin
    ;; fetch escrow
    (match (map-get? escrows {id: id})
      escrow
      (let (
             (buyer (get buyer escrow))
             (seller (get seller escrow))
             (arbiter (get arbiter escrow))
             (amount (get amount escrow))
             (deposited (get deposited escrow))
             (status (get status escrow))
           )
        ;; only buyer can deposit
        (asserts! (is-eq tx-sender buyer) (err ERR_NOT_BUYER))
        ;; only if not already funded
        (asserts! (is-eq deposited false) (err ERR_ALREADY_FUNDED))
        ;; transfer STX from buyer to contract
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
          success-response (ok (begin
            (map-set escrows {id: id}
                     {
                      buyer: buyer,
                      seller: seller,
                      arbiter: arbiter,
                      amount: amount,
                      deposited: true,
                      status: STATUS_FUNDED,
                      deadline: (get deadline escrow)})
            true))
          error-response (err ERR_TRANSFER_FAILED))
      )
      (err ERR_NOT_FOUND))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Release funds to seller
;; - Can be called by buyer or arbiter when escrow is funded
(define-public (release (id uint))
  (begin
    (match (map-get? escrows {id: id})
      escrow
      (let (
             (buyer (get buyer escrow))
             (seller (get seller escrow))
             (arbiter (get arbiter escrow))
             (amount (get amount escrow))
             (deposited (get deposited escrow))
             (status (get status escrow))
           )
        ;; must be funded
        (asserts! (is-eq status STATUS_FUNDED) (err ERR_NOT_FUNDED))
        ;; only buyer or arbiter can release
        (asserts! (or (is-eq tx-sender buyer) (is-eq tx-sender arbiter))
                  (err ERR_NOT_AUTHORIZED))
        ;; transfer STX from contract to seller
        (match (stx-transfer? amount (as-contract tx-sender) seller)
          success-response (ok (begin
            (map-set escrows {id: id}
                     {
                      buyer: buyer,
                      seller: seller,
                      arbiter: arbiter,
                      amount: amount,
                      deposited: false,
                      status: STATUS_RELEASED,
                      deadline: (get deadline escrow)})
            true))
          error-response (err ERR_TRANSFER_FAILED))
      )
      (err ERR_NOT_FOUND))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Refund buyer
;; - Can be called by seller or arbiter when escrow is funded
(define-public (refund (id uint))
  (begin
    (match (map-get? escrows {id: id})
      escrow
      (let (
             (buyer (get buyer escrow))
             (seller (get seller escrow))
             (arbiter (get arbiter escrow))
             (amount (get amount escrow))
             (status (get status escrow))
           )
        ;; must be funded
        (asserts! (is-eq status STATUS_FUNDED) (err ERR_NOT_FUNDED))
        ;; only seller or arbiter can refund
        (asserts! (or (is-eq tx-sender seller) (is-eq tx-sender arbiter))
                  (err ERR_NOT_AUTHORIZED))
        ;; transfer STX from contract back to buyer
        (match (stx-transfer? amount (as-contract tx-sender) buyer)
          success-response (ok (begin
            (map-set escrows {id: id}
                     {
                      buyer: buyer,
                      seller: seller,
                      arbiter: arbiter,
                      amount: amount,
                      deposited: false,
                      status: STATUS_REFUNDED,
                      deadline: (get deadline escrow)})
            true))
          error-response (err ERR_TRANSFER_FAILED))
      )
      (err ERR_NOT_FOUND))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Cancel an escrow (buyer only) before funding
(define-public (cancel (id uint))
  (begin
    (match (map-get? escrows {id: id})
      escrow
      (let (
             (buyer (get buyer escrow))
             (status (get status escrow))
           )
        (asserts! (is-eq tx-sender buyer) (err ERR_NOT_BUYER))
        ;; only possible if pending (not funded)
        (asserts! (is-eq status STATUS_PENDING) (err ERR_INVALID_STATUS))
        (map-set escrows {id: id}
                 {
                  buyer: buyer,
                  seller: (get seller escrow),
                  arbiter: (get arbiter escrow),
                  amount: (get amount escrow),
                  deposited: false,
                  status: STATUS_CANCELLED,
                  deadline: (get deadline escrow)})
        (ok true))
      (err ERR_NOT_FOUND))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Auto-refund by buyer after deadline
;; - Allows buyer to reclaim funds if deadline passed and still funded.
(define-public (auto-refund (id uint))
  (begin
    (match (map-get? escrows {id: id})
      escrow
      (let (
             (buyer (get buyer escrow))
             (amount (get amount escrow))
             (status (get status escrow))
             (deadline (get deadline escrow))
           )
        ;; only buyer can call auto-refund
        (asserts! (is-eq tx-sender buyer) (err ERR_NOT_BUYER))
        (asserts! (is-eq status STATUS_FUNDED) (err ERR_NOT_FUNDED))
        ;; deadline must be reached or passed
        (asserts! (>= (stx-get-balance tx-sender) deadline) (err ERR_DEADLINE_NOT_REACHED))
        ;; transfer STX back to buyer
        (match (stx-transfer? amount (as-contract tx-sender) buyer)
          success-response (ok (begin
            (map-set escrows {id: id}
                     {
                      buyer: buyer,
                      seller: (get seller escrow),
                      arbiter: (get arbiter escrow),
                      amount: amount,
                      deposited: false,
                      status: STATUS_REFUNDED,
                      deadline: deadline})
            true))
          error-response (err ERR_TRANSFER_FAILED))
      )
      (err ERR_NOT_FOUND))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Admin/read helpers: list status constant meanings (read-only)
(define-read-only (status-meaning (s uint))
  (ok (if (is-eq s STATUS_PENDING)
          {id: s, meaning: "PENDING"}
      (if (is-eq s STATUS_FUNDED)
          {id: s, meaning: "FUNDED"}
      (if (is-eq s STATUS_RELEASED)
          {id: s, meaning: "RELEASED"}
      (if (is-eq s STATUS_REFUNDED)
          {id: s, meaning: "REFUNDED"}
      (if (is-eq s STATUS_CANCELLED)
          {id: s, meaning: "CANCELLED"}
          {id: s, meaning: "UNKNOWN"})))))
  )
)
