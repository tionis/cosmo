#!/bin/env janet
(import ./init :as "cosmo")
(import ./base64)
(use spork)

(def store/help
  `Store allows storing objects and strings in the cosmo git repo, available subcommands are:
    get $KEY - Prints the value for key without extra newline
    set $KEY $VALUE - Set a key to the given value
    ls $OPTIONAL_PATTERN - If glob-pattern was given, list all keys matching it, else list all
    rm $KEY - Delete the key`)

(def store/argparse
  ["Store allows storing objects and strings in the cosmo git repo"
   "global" {:kind :flag
             :short "g"
             :help "Work on global store, this is the default"}
   "local" {:kind :flag
            :short "l"
            :help "Work on local store"}
   "groups" {:kind :accumulate
             :short "t"
             :help "The groups the secret should be encrypted for (implies --global)"}
   :default {:kind :accumulate
             :help store/help}])

(defn print_val [val]
  (if (= (type val) :string)
      (print val)
      (print (string/format "%j" val))))

(defn store/handler [key]
  (setdyn :args @[((dyn :args) 0) ;(slice (dyn :args) 2 -1)])
  (def args (argparse/argparse ;store/argparse))
  (unless args (os/exit 1))
  (if (not (args :default))
    (do (print store/help)
        (os/exit 0)))
  # TODO pass --groups to store once encryption support is there
  (if (args "groups") (put args "global" true))
  (if (args "global") (put args "local" nil))
  (case ((args :default) 0)
    "get" (if (args "local")
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/cache/get ((args :default) 1))]
                (print_val val)))
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/store/get ((args :default) 1))]
                (print_val val))))
    "set" (if (args "local")
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/cache/set ((args :default) 1) ((args :default) 2)))
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/store/set ((args :default) 1) ((args :default) 2))))
    "ls"  (if (args "local") # TODO think of better way for passing list to user (human readable key=value but if --json is given print list as json?)
            (let [patt (if (> (length (args :default)) 1) () nil)
                list (cosmo/cache/ls-contents patt)]
              (print (string/format "%P" list)))
            (let [patt (if (> (length (args :default)) 1) () nil)
                list (cosmo/store/ls-contents patt)]
              (print (string/format "%P" list))))
    "rm"  (if (args "local")
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/cache/rm ((args :default) 1)))
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/store/rm ((args :default) 1))))
    (do (eprint "Unknown subcommand")
        (os/exit 1))))

(defn universal-vars/handler [key])
    #["universal_vars" "help"] (universal_vars/help) # TODO diff between global and local universal vars
    #["universal_vars" "set" key value] (universal-vars/set key value)
    #["universal_vars" "get" key] (universal-vars/get key)
    #["universal_vars" "rm" key] (universal-vars/set key nil)
    #["universal_vars" "export"] (universal-vars/export))

(defn daemon/help []
  (print `the cosmod daemon runs in the background to regularily initiate a sync operation
          and also allows some more functionality to be developed
          cosmod subcommands:
            start - start the daemon
            stop - stop the daemon`))

(defn sync/status []
  (if (cosmo/sync/enabled?)
    (os/exit 0)
    (os/exit 1)))

(defn sync/status/print []
  (if (cosmo/sync/enabled?)
    (print "Sync enabled!")
    (print "Sync disabled!")))

(defn get_prompt []
  (def sync_status (if (cosmo/sync/enabled?) "" "sync:disabled "))
  (def changes_array (string/split "\n" ((cosmo/git "status" "--porcelain=v1") :text)))
  (var changes_count (length changes_array))
  (if (= changes_count 1) (if (= (changes_array 0) "") (set changes_count 0)))
  (def changes_status (if (> changes_count 0) (string changes_count " uncommitted changes ")))
  (prin "\x1b[31m" sync_status changes_status "\x1b[37m")(flush))

(defn help []
  (print "Top-Level commands for cosmo")
  (print "  help - this help message")
  (print "  get_prompt - returns shell prompt module text")
  (print "  init - intialize a new node")
  (print "  sync - sync commands, for help use cosmo sync help")
  (print "  universal_vars - Universal Variables, check cosmo universal_vars help")
  (print "  list_unsigned_files - list all files that were last modified in a unsigned commit")
  (print "  verify_file - check if last modification of file was signed")
  (print "  store - store commands, for help use cosmo store help")
  (print "  secrets - secrets commands, for help use cosmo secrets help")
  (print "  get_nodes_in_group - get nodes in group"))

(defn main [_ & raw_args]
  (match raw_args
    ["init"] (cosmo/init)
    ["help"] (help)
    ["get_prompt"] (get_prompt)
    ["id"] (print (base64/encode (cosmo/cache/get "node/sign/pubkey")))
    ["short-id"] (print (slice (base64/encode (cosmo/cache/get "node/sign/pubkey")) 0 8))
    #["s"] (status)
    ["se"] (cosmo/sync/enable)
    ["sd"] (cosmo/sync/disable)
    ["ss"] (sync/status)
    ["store" & args] (store/handler args)
    ["sync" "enabled"] (sync/status)
    ["sync" "status"] (sync/status/print)
    ["sync" "enable"] (cosmo/sync/enable)
    ["sync" "disable"] (cosmo/sync/disable)
    #["sync" "notes"] (sync_notes)
    ["sync" "after_lock"] (cosmo/sync/after_lock)
    ["sync"] (cosmo/sync/sync)
    #["daemon" "start"] (cosmo/daemon/start)
    #["daemon" "stop"] (cosmo/daemon/stop)
    #["daemon" "help"] (cosmo/daemon/help)
    #["daemon"] (cosmo/daemon/help)
    #["motd" "add" source id] (motd/add source id)
    #["motd" "add" source] (motd/add source (uuid/new))
    #["motd" "add"] (motd/add "unknown" (uuid/new))
    #["motd" "rm" id] (motd/rm id)
    #["motd"] (motd)
    ["get_node_name"] (print (cosmo/cache/get "node/name"))
    ["universal_vars" & args] (universal-vars/handler args)
    #["verify_file" file] (verify_file_command file)
    #["list_unsigned_files"] (list_unsigned_files)
    #["get_nodes_in_group" group] (get_nodes_in_group group) # TODO think of better name and change it everywhere
    _ (os/exit (cosmo/git/loud ;raw_args))))
