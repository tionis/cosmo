(use ./util)
(import flock)
(import ./sync)

(defn after_lock []
  # TODO start multiple parallel loops here
  # one that runs every x minutes where x is (/ 1 sync_pulse_frequency) where sync_pulse_frquency is loaded from git config and defaults to .2
  # -> add job check to sync
  # start main supervisor which starts the sub supervisors for the registered services
  # TODO find a way to run janet code dynamically in a sandbox or smth like that
  (forever
    (sync/sync)
    (os/sleep 300)))

(defn stop []
  (error "Not implemented"))

(defn start []
  (try (do (def sync_lock (flock/acquire (string (get-cosmo-dir) "/daemon.lock") :noblock :exclusive))
         (if (= sync_lock nil)
           (do (print "Daemon already running!")
             (os/exit 1))
           (print "Started daemon."))
         (after_lock)
         (flock/release sync_lock))
    ([err]
      (pp err)
      (print "Normal file locking failed, falling back to using flock...")
      (os/execute ["flock" "-x" "-n" (string (get-cosmo-dir) "/sync.lock") "-c" "cosmo daemon after_lock"] :p))))
