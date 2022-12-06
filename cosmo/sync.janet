(use ./util)
(use ./store)
(import flock)

(defn enabled? [] (not (cache/get "sync/disabled")))

(defn execute_pre_sync_hook []
  (def path (path/join (get-cosmo-dir) "hooks" "pre-sync"))
  (if (file_exists? path)
      (do (print "Executing pre-sync-hook...")
          (if (= (os/execute [path]) 0)
            true
            (do (pp {:result (os/execute [path]) :location "pre-sync"})
                false)))
    true))

(defn execute_post_sync_hook []
  (def path (path/join (get-cosmo-dir) "hooks" "post-sync"))
  (if (file_exists? path)
    (do (print "Executing post-sync-hook...")
        (= (os/execute [path]) 0))
    true))

(defn after_lock []
  (def head_before_sync ((git/fail_on_error "rev-parse" "HEAD") :text))
  (git/loud "pull" "--autostash" "--no-edit" "--recurse-submodules=on-demand")
  # check if all commits since head_before_sync were signed, abort if not NOTE: this may be to radical and break things, maybe just define that the last edit of some important files should be signed
  # secrets_generate-allowed-signers # TODO only do this when there were relevant changes
  # secrets_generate-allowed-keys # TODO only do this when there were relevant changes
  # cosmo:ensure_key-added (can probably be scrapped with a conditional error detection or assumed to be taken care of during init)
  #if type -q systemctl
  #if cosmo:changed $HEAD_BEFORE_SYNC $__fish_config_dir/data/services/$NODE_NAME
  #    system:services:setup
  #end
  #end
  #git add -A (still needed?)
  (if (not (= ((git "rev-parse" "origin") :text) ((git "rev-parse" "main") :text)))
    (do (print "Starting push...")
      (git/loud "push"))
    (print "Nothing to push"))
  (if (not (execute_post_sync_hook))
      (eprint "Post_sync_hook failed!")))

(defn sync []
  # TODO check if internet and abort if not (this has to be able to be disabled )(maybe check config?)
  # TODO split this up and move parts of it to cli
  (if (enabled?)
    (do
      (try (do (prin "Acquiring sync lock... ")(flush)
             (def sync_lock (get-sync-lock))
             (print "Done.")
             (if (not (execute_pre_sync_hook))
               (do (print "Sync aborted due to pre-sync hook")
                 (os/exit 1)))
             (after_lock)
             (flock/release sync_lock))
        ([err]
          (pp err)
          (print "Normal file locking failed, falling back to using flock...")
          (os/execute ["flock" "-x" (string (get-cosmo-dir) "/sync.lock") "-c" "cosmo sync after_lock"] :p))))
    (eprint "Sync disabled!")))

(defn disable [] (cache/set "sync/disabled" true))

(defn enable [] (cache/set "sync/disabled" nil))

#(defn notes []
  # TODO fix this
  #(git/loud "fetch" "origin" "refs/notes/*:refs/notes/*")
  #(git/loud "push" "origin" "'refs/notes/*"))
