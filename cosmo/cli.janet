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

(defn store/handler [args]
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
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/cache/ls-contents patt)]
              (print (string/format "%P" list)))
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/store/ls-contents patt)]
              (print (string/format "%P" list))))
    "rm"  (if (args "local")
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/cache/rm ((args :default) 1)))
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/store/rm ((args :default) 1))))
    (do (eprint "Unknown subcommand")
        (os/exit 1))))

(def universal-vars/help
  `Universal vars are environment variables that are sourced at the beginning of a shell session.
  This allows to have local env-vars that are either machine specific or shared among all.
  To create an environment variable use the store, all variables are stored under the vars/* prefix
  Available Subcommands:
    export $optional_pattern - return the  environment variables matching pattern, all if none is given in a format that can be evaled by posix shells`)

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

(defn hooks/help []
  (print `Execute cosmo hooks, available subcommands:
            pre-sync - execute pre-sync hook
            post-sync - execute post-sync hook
            help - show this help message`))

(defn motd/help []
  (print `motd - manage your motd by appending message to the greeting in you shell
          Available subcommands:
            add $optional_source $optional_id_only_when_source_given - add a message (that is read from stdin) to the motd log
            rm $id - remove message with id
            ls $optional_pattern - list messages whose id matches the optional pattern
            help - this help`))

(defn hosts/help []
  (print `The hosts subsystem manages your ssh hosts
          Following subcommands are supported
            help - this help
            add $address - add address to hosts db, when executed ssh checks the host keys and adds them to the store
            import - import the hosts in the database into local hosts file`))

(defn help []
  (print `Top-Level commands for cosmo
            help - this help message
            get_prompt - returns shell prompt module text
            init - intialize a new node
            sync - sync commands, for help use cosmo sync help
            vars - Universal Environment Variables, check cosmo vars help
            store - store commands, for help use cosmo store help
            motd - motd commands, for help use cosmo motd help`))

(defn main [_ & raw_args]
  (match raw_args
    ["init"] (cosmo/init)
    ["help"] (help)
    ["get_prompt"] (get_prompt)
    ["id"] (print (cosmo/id))
    ["short-id"] (print (cosmo/id/short))
    ["safe-id"] (print (cosmo/id/safe))
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
    ["hooks" "pre-sync"] (if (cosmo/sync/execute_pre_sync_hook) (os/exit 0) (os/exit 1))
    ["hooks" "post-sync"] (if (cosmo/sync/execute_post_sync_hook) (os/exit 0) (os/exit 1))
    ["hooks" "help"] (hooks/help)
    ["hooks"] (hooks/help)
    #["daemon" "start"] (cosmo/daemon/start)
    #["daemon" "stop"] (cosmo/daemon/stop)
    #["daemon" "help"] (cosmo/daemon/help)
    #["daemon"] (cosmo/daemon/help)
    ["motd" "add" source id] (cosmo/motd/add source id (file/read stdin :all))
    ["motd" "add" source] (cosmo/motd/add source (cosmo/uuid/new) (file/read stdin :all))
    ["motd" "add"] (cosmo/motd/add "unknown" (cosmo/uuid/new) (file/read stdin :all))
    ["motd" "rm" id] (cosmo/motd/rm id)
    ["motd" "ls" &opt patt] (let [items (cosmo/motd/ls-contents patt)]
                                 (eachk key items
                                   (pp (merge (items key) {:id key}))))
    ["motd" "help"] (motd/help)
    ["motd"] (prin (string/join (cosmo/motd/ls-formatted) "\n\n"))
    ["get_node_name"] (print (cosmo/cache/get "node/name"))
    ["vars" "export"] (print (cosmo/universal-vars/export))
    ["vars" "help"] (print universal-vars/help)
    ["vars"] (print universal-vars/help)
    ["hosts" "add" address] (cosmo/hosts/add address)
    ["hosts" "import"] (cosmo/hosts/import)
    ["hosts" "help"] (hosts/help)
    ["hosts"] (hosts/help)
    #["verify_file" file] (verify_file_command file)
    #["list_unsigned_files"] (list_unsigned_files)
    #["get_nodes_in_group" group] (get_nodes_in_group group) # TODO think of better name and change it everywhere
    _ (os/exit (cosmo/git/loud ;raw_args))))
