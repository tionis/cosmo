#!/bin/env janet
(import spork :prefix "" :export true)
(import jhydro :export true)
(import sqlite3 :export true)
(import flock :export true)
(import ./glob :export true)
(import ./uuid :export true)
(import ./base64 :export true)
(import ./util :prefix "" :export true)
(import ./store :prefix "" :export true)
(import ./universal-vars :export true)
(import ./crypto :export true)
(import ./daemon :export true)
(import ./sync :export true)
(import ./hosts :export true)

(defn status []
  (git/loud "status"))

(defn init
  "execute the interactive initialization process, this is idempotent"
  []
  (print "Starting initialization of cosmo repo...")
  (print "Starting node init")
  (var old_node_name (cache/get "node/name"))
  (if (or (not old_node_name) (= old_node_name ""))
      (set old_node_name (exec-slurp "uname" "-n")))
  (prin (string "node.name[" old_node_name "]> "))(flush)
  (def node_name (string/trim (file/read stdin :line)))
  (def new_node_name (if (= node_name "") old_node_name node_name))
  (cache/set "node/name" new_node_name)

  # TODO check if own id is already in store
  # if not add it

  # TODO check if node is already in any groups
  # if not print command to be execute on a :main node to add this node to some groups


  # TODO add following command somewhere else
  # init_node $id_of_node_to_add $group1 $group2 $group3
  # this should be executed on a :main node (fails on other nodes)
  # it will add the node to the groups and if :main is one of the mentioned groups
  # it will add the new node to the sigchain
  # then it will execute (each group groups (store/reencrypt group)) to reencrypt all secrets for the new node
  # for this to work each secret is always also encrypted for :main
  # while init_node is execute somewhere else the node waits, until the user says it is added or they want to skip this part
  # if not skipped (git pull) and then check if node was added somewhere with a valid signature

  # MAYBE also set git ssh key for signing here, we could also guard against other possible miconfiguration here
  # check if clone is successfull, else tell the user and wait for confirmation to try again, start completly from the beginning or abort the whole init process

  (let [source (path/join (get_cosmo_config_dir) "hooks" "pre-sync")
        target (path/join (get-cosmo-dir) "hooks" "pre-sync")]
    (if (file_exists? source)
        (do (spit target (slurp source))
            (os/chmod target "rwx------"))))
  (let [source (path/join (get_cosmo_config_dir) "hooks" "post-sync")
        target (path/join (get-cosmo-dir) "hooks" "post-sync")]
    (if (file_exists? source)
        (do (spit target (slurp source))
            (os/chmod target "rwx------"))))

  # TODO execute script at .config/cosmo/init.janet

  (git "config" "gpg.ssh.allowedSignersFile" (string (os/getenv "HOME") "/.ssh/allowed_signers"))
  (if (cache/get "node/sign/secret-key")
      (print "Skipping key generation as there are keys saved.")
      (do (prin "Generating and saving machine keys...")(flush)
          (crypto/gen_keys)
          (print "  Done.")))
  (print "Finished.")
  (prin "Importing hosts db...")(flush)
  (hosts/import)
  (print " Done."))

(defn id "returns the id of the current node" [] (base64/encode (cache/get "node/sign/public-key")))

(defn motd/add [source id message] (cache/set (string "motd/" id) {:source source :message message}))
(defn motd/rm [id] (cache/rm (string "motd/" id)))
(defn motd/ls-contents [&opt patt]
  (if patt
      (cache/ls-contents (string "motd/" patt))
      (cache/ls-contents "motd/*")))
(defn motd/ls-formatted [&opt patt]
  (def ret @[])
  (def items (motd/ls-contents patt))
  (eachk key items
    (def item (items key))
    (array/push ret (string "{:source "(item :source) " :id " key "}\nMessage:\n" (item :message))))
  ret)
