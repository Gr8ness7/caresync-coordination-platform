;; caresync-coordinator
;; 
;; This contract serves as the central coordination hub for the CareSync platform,
;; enabling caregivers to create and manage care circles, coordinate tasks, and
;; maintain shared records of care activities for recipients. It provides secure
;; mechanisms for caregiver authorization, task management, and status updates
;; while ensuring data privacy across different care circles.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-ALREADY-EXISTS u101)
(define-constant ERR-DOES-NOT-EXIST u102)
(define-constant ERR-INVALID-TASK u103)
(define-constant ERR-TASK-ALREADY-CLAIMED u104)
(define-constant ERR-TASK-NOT-CLAIMED u105)
(define-constant ERR-TASK-ALREADY-COMPLETED u106)
(define-constant ERR-NOT-TASK-OWNER u107)
(define-constant ERR-INVALID-CARE-RECIPIENT u108)
(define-constant ERR-ALREADY-VERIFIED u109)
(define-constant ERR-NOT-CAREGIVER u110)
(define-constant ERR-INVALID-STATUS u111)

;; Data structures

;; Care recipient registry
;; Maps recipient ID to their care circle administrator
(define-map care-recipients 
  { recipient-id: uint } 
  { admin: principal, name: (string-utf8 100), created-at: uint }
)

;; Authorized caregivers for each care recipient
(define-map care-circle-members
  { recipient-id: uint, caregiver: principal }
  { role: (string-utf8 20), added-at: uint, added-by: principal }
)

;; List of caregivers per recipient for efficient querying
(define-map recipient-caregivers
  { recipient-id: uint }
  { caregivers: (list 50 principal) }
)

;; Task data structure
(define-map tasks
  { task-id: uint }
  {
    recipient-id: uint,
    title: (string-utf8 100),
    description: (string-utf8 500),
    created-by: principal,
    created-at: uint,
    due-date: uint,
    priority: (string-utf8 10),
    status: (string-utf8 20),
    assigned-to: (optional principal),
    completed-at: (optional uint),
    completed-by: (optional principal),
    verified-at: (optional uint),
    verified-by: (optional principal)
  }
)

;; Tasks associated with a recipient
(define-map recipient-tasks
  { recipient-id: uint }
  { task-ids: (list 500 uint) }
)

;; Care updates/notes for recipients
(define-map care-updates
  { update-id: uint }
  {
    recipient-id: uint,
    created-by: principal,
    created-at: uint,
    content: (string-utf8 1000),
    update-type: (string-utf8 50),
    related-task-id: (optional uint)
  }
)

;; List of updates per recipient for efficient querying
(define-map recipient-updates
  { recipient-id: uint }
  { update-ids: (list 500 uint) }
)

;; Global counters for generating unique IDs
(define-data-var next-recipient-id uint u1)
(define-data-var next-task-id uint u1)
(define-data-var next-update-id uint u1)

;; Private functions

;; Helper function to check if a principal is an authorized caregiver for a recipient
(define-private (is-authorized-caregiver (recipient-id uint) (caregiver principal))
  (default-to false (map-get? care-circle-members { recipient-id: recipient-id, caregiver: caregiver }))
)

;; Helper function to check if a principal is the admin for a care recipient
(define-private (is-admin-for-recipient (recipient-id uint) (admin principal))
  (let ((recipient (map-get? care-recipients { recipient-id: recipient-id })))
    (and 
      (is-some recipient)
      (is-eq (get admin (unwrap-panic recipient)) admin)
    )
  )
)

;; Helper to add a caregiver to the recipient-caregivers list
(define-private (add-caregiver-to-list (recipient-id uint) (caregiver principal))
  (let ((existing-list (default-to { caregivers: (list) } 
                        (map-get? recipient-caregivers { recipient-id: recipient-id }))))
    (map-set recipient-caregivers
      { recipient-id: recipient-id }
      { caregivers: (unwrap-panic (as-max-len? (append (get caregivers existing-list) caregiver) u50)) }
    )
  )
)

;; Helper to add a task ID to the recipient-tasks list
(define-private (add-task-to-recipient (recipient-id uint) (task-id uint))
  (let ((existing-list (default-to { task-ids: (list) } 
                        (map-get? recipient-tasks { recipient-id: recipient-id }))))
    (map-set recipient-tasks
      { recipient-id: recipient-id }
      { task-ids: (unwrap-panic (as-max-len? (append (get task-ids existing-list) task-id) u500)) }
    )
  )
)

;; Helper to add an update ID to the recipient-updates list
(define-private (add-update-to-recipient (recipient-id uint) (update-id uint))
  (let ((existing-list (default-to { update-ids: (list) } 
                        (map-get? recipient-updates { recipient-id: recipient-id }))))
    (map-set recipient-updates
      { recipient-id: recipient-id }
      { update-ids: (unwrap-panic (as-max-len? (append (get update-ids existing-list) update-id) u500)) }
    )
  )
)

;; Read-only functions

;; Get care recipient details
(define-read-only (get-care-recipient (recipient-id uint))
  (map-get? care-recipients { recipient-id: recipient-id })
)

;; Get caregiver information for a recipient
(define-read-only (get-caregiver-info (recipient-id uint) (caregiver principal))
  (map-get? care-circle-members { recipient-id: recipient-id, caregiver: caregiver })
)

;; Get all caregivers for a recipient
(define-read-only (get-all-caregivers (recipient-id uint))
  (default-to { caregivers: (list) } (map-get? recipient-caregivers { recipient-id: recipient-id }))
)

;; Get task details
(define-read-only (get-task (task-id uint))
  (map-get? tasks { task-id: task-id })
)

;; Get all tasks for a recipient
(define-read-only (get-recipient-tasks (recipient-id uint))
  (default-to { task-ids: (list) } (map-get? recipient-tasks { recipient-id: recipient-id }))
)

;; Get care update details
(define-read-only (get-care-update (update-id uint))
  (map-get? care-updates { update-id: update-id })
)

;; Get all updates for a recipient
(define-read-only (get-recipient-updates (recipient-id uint))
  (default-to { update-ids: (list) } (map-get? recipient-updates { recipient-id: recipient-id }))
)

;; Check if a principal is authorized for a recipient
(define-read-only (is-authorized (recipient-id uint) (user principal))
  (is-some (map-get? care-circle-members { recipient-id: recipient-id, caregiver: user }))
)

;; Public functions

;; Create a new care recipient and care circle
(define-public (create-care-recipient (name (string-utf8 100)))
  (let ((new-id (var-get next-recipient-id))
        (caller tx-sender)
        (timestamp block-height))
    
    ;; Set the new recipient with the caller as admin
    (map-set care-recipients
      { recipient-id: new-id }
      { admin: caller, name: name, created-at: timestamp }
    )
    
    ;; Add the creator as the first caregiver with admin role
    (map-set care-circle-members
      { recipient-id: new-id, caregiver: caller }
      { role: "admin", added-at: timestamp, added-by: caller }
    )
    
    ;; Initialize the caregivers list with the admin
    (map-set recipient-caregivers
      { recipient-id: new-id }
      { caregivers: (list caller) }
    )
    
    ;; Increment the recipient ID counter
    (var-set next-recipient-id (+ new-id u1))
    
    ;; Return the new recipient ID
    (ok new-id)
  )
)

;; Add a caregiver to a care circle
(define-public (add-caregiver (recipient-id uint) (caregiver principal) (role (string-utf8 20)))
  (let ((caller tx-sender)
        (timestamp block-height))
    
    ;; Check if caller is authorized as an admin
    (asserts! (is-admin-for-recipient recipient-id caller) (err ERR-NOT-AUTHORIZED))
    
    ;; Check if recipient exists
    (asserts! (is-some (map-get? care-recipients { recipient-id: recipient-id })) (err ERR-DOES-NOT-EXIST))
    
    ;; Check if caregiver is already in the care circle
    (asserts! (is-none (map-get? care-circle-members { recipient-id: recipient-id, caregiver: caregiver })) 
              (err ERR-ALREADY-EXISTS))
    
    ;; Add the caregiver to the care circle
    (map-set care-circle-members
      { recipient-id: recipient-id, caregiver: caregiver }
      { role: role, added-at: timestamp, added-by: caller }
    )
    
    ;; Add caregiver to the list of caregivers for this recipient
    (add-caregiver-to-list recipient-id caregiver)
    
    (ok true)
  )
)

;; Remove a caregiver from a care circle
(define-public (remove-caregiver (recipient-id uint) (caregiver principal))
  (let ((caller tx-sender))
    
    ;; Check if caller is authorized as an admin
    (asserts! (is-admin-for-recipient recipient-id caller) (err ERR-NOT-AUTHORIZED))
    
    ;; Check if caregiver exists in the care circle
    (asserts! (is-some (map-get? care-circle-members { recipient-id: recipient-id, caregiver: caregiver })) 
              (err ERR-DOES-NOT-EXIST))
    
    ;; Cannot remove self if you're the last admin
    (asserts! (not (and 
                    (is-eq caregiver caller)
                    (is-admin-for-recipient recipient-id caller)
                    (is-eq (len (get caregivers (get-all-caregivers recipient-id))) u1)))
              (err ERR-NOT-AUTHORIZED))
    
    ;; Remove the caregiver from the care circle
    (map-delete care-circle-members { recipient-id: recipient-id, caregiver: caregiver })
    
    ;; Note: We don't remove from the recipient-caregivers list as it would require rebuilding the list
    ;; In a production environment, we would implement a proper remove function
    
    (ok true)
  )
)

;; Create a new task for a care recipient
(define-public (create-task 
                (recipient-id uint) 
                (title (string-utf8 100)) 
                (description (string-utf8 500))
                (due-date uint)
                (priority (string-utf8 10)))
  (let ((new-id (var-get next-task-id))
        (caller tx-sender)
        (timestamp block-height))
    
    ;; Check if caller is authorized for this recipient
    (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
    
    ;; Create the new task
    (map-set tasks
      { task-id: new-id }
      {
        recipient-id: recipient-id,
        title: title,
        description: description,
        created-by: caller,
        created-at: timestamp,
        due-date: due-date,
        priority: priority,
        status: "open",
        assigned-to: none,
        completed-at: none,
        completed-by: none,
        verified-at: none,
        verified-by: none
      }
    )
    
    ;; Add task to recipient's task list
    (add-task-to-recipient recipient-id new-id)
    
    ;; Increment the task ID counter
    (var-set next-task-id (+ new-id u1))
    
    (ok new-id)
  )
)

;; Claim a task (assign to self)
(define-public (claim-task (task-id uint))
  (let ((caller tx-sender)
        (task (map-get? tasks { task-id: task-id })))
    
    ;; Check if task exists
    (asserts! (is-some task) (err ERR-DOES-NOT-EXIST))
    
    (let ((task-data (unwrap-panic task))
          (recipient-id (get recipient-id task-data)))
      
      ;; Check if caller is authorized for this recipient
      (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
      
      ;; Check if task is unassigned or open
      (asserts! (is-eq (get status task-data) "open") (err ERR-TASK-ALREADY-CLAIMED))
      
      ;; Update task status and assignment
      (map-set tasks
        { task-id: task-id }
        (merge task-data {
          status: "claimed",
          assigned-to: (some caller)
        })
      )
      
      (ok true)
    )
  )
)

;; Mark a task as completed
(define-public (complete-task (task-id uint) (notes (optional (string-utf8 500))))
  (let ((caller tx-sender)
        (task (map-get? tasks { task-id: task-id }))
        (timestamp block-height))
    
    ;; Check if task exists
    (asserts! (is-some task) (err ERR-DOES-NOT-EXIST))
    
    (let ((task-data (unwrap-panic task))
          (recipient-id (get recipient-id task-data)))
      
      ;; Check if caller is authorized for this recipient
      (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
      
      ;; Check if task is claimed by caller
      (asserts! (and 
                  (is-eq (get status task-data) "claimed")
                  (is-eq (some caller) (get assigned-to task-data)))
                (err ERR-NOT-TASK-OWNER))
      
      ;; Update task as completed
      (map-set tasks
        { task-id: task-id }
        (merge task-data {
          status: "completed",
          completed-at: (some timestamp),
          completed-by: (some caller)
        })
      )
      
      ;; Optionally add a care update with completion notes
      (match notes
        note-content (begin
          (let ((update-id (var-get next-update-id)))
            (map-set care-updates
              { update-id: update-id }
              {
                recipient-id: recipient-id,
                created-by: caller,
                created-at: timestamp,
                content: note-content,
                update-type: "task-completion",
                related-task-id: (some task-id)
              }
            )
            (add-update-to-recipient recipient-id update-id)
            (var-set next-update-id (+ update-id u1))
          )
          (ok true)
        )
        (ok true)
      )
    )
  )
)

;; Verify a completed task
(define-public (verify-task (task-id uint))
  (let ((caller tx-sender)
        (task (map-get? tasks { task-id: task-id }))
        (timestamp block-height))
    
    ;; Check if task exists
    (asserts! (is-some task) (err ERR-DOES-NOT-EXIST))
    
    (let ((task-data (unwrap-panic task))
          (recipient-id (get recipient-id task-data)))
      
      ;; Check if caller is authorized for this recipient
      (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
      
      ;; Check if task is completed
      (asserts! (is-eq (get status task-data) "completed") (err ERR-TASK-NOT-CLAIMED))
      
      ;; Check if task isn't already verified
      (asserts! (is-none (get verified-at task-data)) (err ERR-ALREADY-VERIFIED))
      
      ;; Check that verifier isn't the same as completer
      (asserts! (not (is-eq (some caller) (get completed-by task-data))) (err ERR-NOT-AUTHORIZED))
      
      ;; Update task as verified
      (map-set tasks
        { task-id: task-id }
        (merge task-data {
          status: "verified",
          verified-at: (some timestamp),
          verified-by: (some caller)
        })
      )
      
      (ok true)
    )
  )
)

;; Post a care update/note for a recipient
(define-public (post-care-update 
                (recipient-id uint) 
                (content (string-utf8 1000))
                (update-type (string-utf8 50))
                (related-task-id (optional uint)))
  (let ((caller tx-sender)
        (timestamp block-height)
        (update-id (var-get next-update-id)))
    
    ;; Check if caller is authorized for this recipient
    (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
    
    ;; If there's a related task, verify it exists and belongs to this recipient
    (when (is-some related-task-id)
      (let ((task (map-get? tasks { task-id: (unwrap-panic related-task-id) })))
        (asserts! (is-some task) (err ERR-INVALID-TASK))
        (asserts! (is-eq recipient-id (get recipient-id (unwrap-panic task))) (err ERR-INVALID-CARE-RECIPIENT))
      )
    )
    
    ;; Create the update
    (map-set care-updates
      { update-id: update-id }
      {
        recipient-id: recipient-id,
        created-by: caller,
        created-at: timestamp,
        content: content,
        update-type: update-type,
        related-task-id: related-task-id
      }
    )
    
    ;; Add update to recipient's update list
    (add-update-to-recipient recipient-id update-id)
    
    ;; Increment the update ID counter
    (var-set next-update-id (+ update-id u1))
    
    (ok update-id)
  )
)

;; Update a recipient's care status
(define-public (update-recipient-status 
                (recipient-id uint) 
                (status-type (string-utf8 50))
                (status-content (string-utf8 1000)))
  (let ((caller tx-sender))
    
    ;; Check if caller is authorized for this recipient
    (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
    
    ;; We'll implement this as a special type of care update
    (post-care-update recipient-id status-content status-type none)
  )
)

;; Reassign a task to another caregiver
(define-public (reassign-task (task-id uint) (new-caregiver principal))
  (let ((caller tx-sender)
        (task (map-get? tasks { task-id: task-id })))
    
    ;; Check if task exists
    (asserts! (is-some task) (err ERR-DOES-NOT-EXIST))
    
    (let ((task-data (unwrap-panic task))
          (recipient-id (get recipient-id task-data)))
      
      ;; Check if caller is authorized for this recipient
      (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
      
      ;; Check if new caregiver is authorized for this recipient
      (asserts! (is-authorized recipient-id new-caregiver) (err ERR-NOT-CAREGIVER))
      
      ;; Check if task is not completed or verified
      (asserts! (not (or 
                      (is-eq (get status task-data) "completed") 
                      (is-eq (get status task-data) "verified")))
                (err ERR-TASK-ALREADY-COMPLETED))
      
      ;; Check if caller is either admin or current assignee
      (asserts! (or 
                 (is-admin-for-recipient recipient-id caller)
                 (is-eq (get assigned-to task-data) (some caller)))
                (err ERR-NOT-AUTHORIZED))
      
      ;; Update task assignment
      (map-set tasks
        { task-id: task-id }
        (merge task-data {
          status: "claimed",
          assigned-to: (some new-caregiver)
        })
      )
      
      (ok true)
    )
  )
)

;; Cancel a task
(define-public (cancel-task (task-id uint) (reason (string-utf8 500)))
  (let ((caller tx-sender)
        (task (map-get? tasks { task-id: task-id }))
        (timestamp block-height))
    
    ;; Check if task exists
    (asserts! (is-some task) (err ERR-DOES-NOT-EXIST))
    
    (let ((task-data (unwrap-panic task))
          (recipient-id (get recipient-id task-data)))
      
      ;; Check if caller is authorized for this recipient
      (asserts! (is-authorized recipient-id caller) (err ERR-NOT-AUTHORIZED))
      
      ;; Check if caller is admin or task creator
      (asserts! (or 
                  (is-admin-for-recipient recipient-id caller)
                  (is-eq (get created-by task-data) caller))
                (err ERR-NOT-AUTHORIZED))
      
      ;; Check if task is not already completed or verified
      (asserts! (not (or 
                      (is-eq (get status task-data) "completed") 
                      (is-eq (get status task-data) "verified")))
                (err ERR-TASK-ALREADY-COMPLETED))
      
      ;; Update task as canceled
      (map-set tasks
        { task-id: task-id }
        (merge task-data {
          status: "canceled"
        })
      )
      
      ;; Add a care update with the cancellation reason
      (let ((update-id (var-get next-update-id)))
        (map-set care-updates
          { update-id: update-id }
          {
            recipient-id: recipient-id,
            created-by: caller,
            created-at: timestamp,
            content: reason,
            update-type: "task-cancellation",
            related-task-id: (some task-id)
          }
        )
        (add-update-to-recipient recipient-id update-id)
        (var-set next-update-id (+ update-id u1))
      )
      
      (ok true)
    )
  )
)