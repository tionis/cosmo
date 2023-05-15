(import flock)
#(import sqlite3 :export true)
(import spork/sh :export true)
(import spork/path :export true)
(import ./filesystem :export true)

(defn home []
  (def p (os/getenv "HOME"))
  (if (or (not p) (= p ""))
      (let [userprofile (os/getenv "USERPROFILE")]
           (if (or (not userprofile) (= userprofile ""))
               (error "Could not determine home directory")
               userprofile))
      p))

(defn get-config-home []
  (def xdg_config_home (os/getenv "XDG_CONFIG_HOME"))
  (if (or (not xdg_config_home) (= xdg_config_home ""))
      (path/join (home) ".config")
      xdg_config_home))

(defn get-cosmo-dir []
  (path/join (get-config-home) "cosmo" ".git"))

(defn get_cosmo_config_dir []
  (path/join (get-config-home) "cosmo"))

(defn get-sync-lock [] # TODO embed function to release them again
  (flock/acquire (string (get-cosmo-dir) "/sync.lock") :block :exclusive))

(defn to_two_digit_string [num]
  (if (< num 9)
    (string "0" num)
    (string num)))

(defn get-iso-datetime []
  (def date (os/date))
  (string (date :year) "-" (to_two_digit_string (date :month)) "-" (to_two_digit_string (date :month-day))
          "T"
          (to_two_digit_string (date :hours)) ":" (to_two_digit_string (date :minutes)) ":" (to_two_digit_string (date :seconds))))

(defn exec-slurp-exit-code [& args]
  (when (dyn :verbose)
     (flush)
     (print "(exec-slurp " ;(interpose " " args) ")"))
   (def proc (os/spawn args :p {:out :pipe}))
   (def out (get proc :out))
   (def buf @"")
   (var exit-code nil)
   (ev/gather
     (:read out :all buf)
     (set exit-code (:wait proc)))
   [(string/trimr buf) exit-code])

(defn exec-slurp
   "Read stdout of subprocess and return it trimmed in a string." 
   [& args]
   (when (dyn :verbose)
     (flush)
     (print "(exec-slurp " ;(interpose " " args) ")"))
   (def proc (os/spawn args :px {:out :pipe}))
   (def out (get proc :out))
   (def buf @"")
   (ev/gather
     (:read out :all buf)
     (:wait proc))
   (string/trimr buf))




#### Git Wrappers #####

(defn git [& args]
  (def streams (os/pipe))
  (def status (os/execute ["git"
                           (string "--git-dir=" (get-cosmo-dir))
                           (string "--work-tree=" (os/getenv "HOME"))
                           ;args]
                          :pe {:out (streams 1) "MERGE_AUTOSTASH" "true"}))
  (ev/close (streams 1))
  {:status status :text (string/trim (string (ev/read (streams 0) :all)))})

(defn git/fail_on_error [& args]
  (def result (git ;args))
  (if (not (= (result :status) 0))
    (error (result :text))
    result))

(defn git/loud [& args]
  (os/execute ["git" 
               (string "--git-dir=" (get-cosmo-dir))
               (string "--work-tree=" (os/getenv "HOME"))
               ;args] :p))

(defn git/loud_fail_on_error [& args]
  (if (not (= (git/loud ;args) 0))
    (error "cfg command failed, see above for logs.")))

(defn changed [commit_hash file_path]
  "return true when the file at file_path has changed since commit_hash'"
  # TODO
  #set file_path (string replace $HOME/ '' $file_path)
  #set files_changed (git diff --name-only $hash..HEAD)

  #for file in $files_changed
  #if test $file = $file_path
  #return true
  #end
  #end
  #return false
  )


(defn create_dirs_if_not_exists [dir]
  (let [meta (os/stat dir)]
    (if (not (and meta (= (meta :mode) :directory)))
      (filesystem/create-directories dir))))

(defn check_git_install []
  (def version (git "version"))
  (def streams (os/pipe))
  (try (os/execute ["git" "version"] :pe {:out (streams 0)})
    ([_err] false))
  (ev/close (streams 1))
  # TODO check version here
  #(def version (string (ev/read (streams 0) :all)))
  true)

(defn get_config_path [] (path/join (get-cosmo-dir) "config.jdn"))

(defn get_cache_path [] (path/join (get-cosmo-dir) "cache.jdn"))

(defn file_exists? [path]
  (def stat (os/stat path))
  (and (not (= stat nil)) (= (stat :mode) :file)))

(def minimum-git-version [2 34 0])

(def minimum-openssh-version [8 0])

(defn is-at-least-version [actual at-least]
  (label is-at-least
    (loop [i :range [0 (min (length actual) (length at-least))]]
      (cond
        (> (actual i) (at-least i)) (return is-at-least true)
        (< (actual i) (at-least i)) (return is-at-least false)))
    true))

(def git-version-grammar (peg/compile
  ~{:patch (number (some :d))
    :minor (number (some :d))
    :major (number (some :d))
    :main (* "git version " :major "." :minor "." :patch)}))

(defn get-git-version []
  (peg/match git-version-grammar (sh/exec-slurp "git" "--version")))

(def openssh-version-grammar (peg/compile
  ~{:minor (number (some :d))
    :major (number (some :d))
    :main (* "OpenSSH_" :major "." :minor)}))

(defn get-openssh-version []
  (peg/match openssh-version-grammar ((sh/exec-slurp-all "ssh" "-V") :err)))

(defn check-deps []
  (when (not (dyn :deps-checked))
    (unless (is-at-least-version (get-git-version) minimum-git-version)
      (error (string "minimum-git-version is "
                     (string/join (map |(string $0)
                                       minimum-git-version) ".")
                     " but detected git version is "
                     (string/join (map |(string $0)
                                       (get-git-version)) "."))))
    (unless (is-at-least-version (get-openssh-version) minimum-openssh-version)
      (error (string "minimum-openssh-version is "
                     (string/join (map |(string $0)
                                       minimum-openssh-version) ".")
                     " but detected openssh version is "
                     (string/join (map |(string $0)
                                       (get-openssh-version)) "."))))
    (setdyn :deps-checked true)))
