(defvar orq-default-session "*orq*")
(defvar orq--process-alist nil
  "Alist of active orq requests.")
(defvar orq-system-prompt "You are an expert programmer. You only provide code when you are highly confident it is correct.")

(define-minor-mode orq-mode
  "Minor mode for interacting with orq."
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c RET") #'orq-send)
    map)
  (if orq-mode
      (setq header-line-format
            (list (concat (propertize " " 'display '(space :align-to 0))
                          (format "%s" (buffer-name)))
                  (propertize " Ready" 'face 'success)))
    (setq header-line-format nil)))

;;;###autoload
(defun orq (name &optional api-key initial)
  (interactive (list (if current-prefix-arg
                         (read-string "Session name: " (generate-new-buffer-name gptel-default-session))
                       orq-default-session)
                     (if (use-region-p)
                         (buffer-substring (region-beginning)
                                           (region-end))
                       (buffer-substring (point-min) (point-max)))))
  (with-current-buffer (get-buffer-create name)
    (text-mode)
    (visual-line-mode 1)
    (unless orq-mode (orq-mode 1))
    (if (bobp) (insert (or initial "")))
    (goto-char (point-max))
    (skip-chars-backward "\t\r\n")
    (when (called-interactively-p 'orq)
      (pop-to-buffer (current-buffer))
      (message "Send your query with %s!"
               (substitute-command-keys "\\[orq-send]")))
    (current-buffer)))

(defun orq--stream-cleanup (process status)
  (let ((proc-buf (process-buffer process)))
    (orq--update-header-line  " Ready" 'success)
    (setf (alist-get process orq--process-alist nil 'remove) nil)
    (kill-buffer proc-buf)))

(defun orq--stream-filter (process output)
  (let* ((content-strs)
         (proc-info (alist-get process orq--process-alist)))
    (with-current-buffer (process-buffer process)
      (save-excursion
        (goto-char (process-mark process))
        (insert output)
        (set-marker (process-mark process) (point-max))
        (funcall #'orq--stream-insert-response output proc-info)))))

(defun orq--update-header-line (msg face)
  (and orq-mode (consp header-line-format)
       (setf (nth 1 header-line-format)
             (propertize msg 'face face))
       (force-mode-line-update)))

;;;###autoload
(defun orq-send ()
  (interactive)
  (message "Querying OpenAI...")
  (let* ((response-pt
          (if (use-region-p)
              (set-marker (make-marker) (region-end))
            (point-max)))
         (orq-buffer (current-buffer))
         ;; let var "full-prompt" be the entire contents of orq-buffer
         (full-prompt (buffer-substring-no-properties (point-min) (point-max))))
    (funcall
     #'orq-get-response
     (list :prompt full-prompt
           :buffer orq-buffer
           :position response-pt))))

(defun orq--get-args ()
  "Produce list of arguments for calling orq."
  ;; return a string with the value "--system" followed by a space, followed by orq-system-prompt, folowed by a space, followed by buffer-content
  (list "--system" orq-system-prompt))

;;;###autoload
(defun orq-get-response (args &optional callback)
    (let* ((orq-args (orq--get-args))
           ;; we do not want to use start-process because apparently call-process-region has
           ;; the capability to specify its input
           (process (apply #'start-process "orq"
                           (generate-new-buffer "*orq-proc*") "orq" orq-args))
           (prompt (plist-get args :prompt)))
      (with-current-buffer orq-buffer
        (save-excursion
          (erase-buffer)))
      (with-current-buffer (process-buffer process)
        (set-process-query-on-exit-flag process nil)
        ;; set callback to stream insert respond
        ;; then in stream filter you run the callback
        (setf (alist-get process orq--process-alist) args)
        (set-process-sentinel process #'orq--stream-cleanup)
        (set-process-filter process #'orq--stream-filter)
        (process-send-string process prompt)
        ;; close the input stream
        (process-send-eof process)
        (process-send-eof process)
        )))

(defun orq--stream-insert-response (response args)
  (let ((status-str  (plist-get response :status))
        (orq-buffer (plist-get args :buffer))
        (start-marker (plist-get args :position)))
    (when response
      (message "streaming response" response)
      (with-current-buffer orq-buffer
        (save-excursion
          (orq--update-header-line " AI Responding..." 'success)
          (goto-char (point-max))
          (insert response))
        (goto-char (point-max))))))
