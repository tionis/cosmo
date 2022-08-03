(use ./util)
(use ./store)

(defn add [address]
  (def parts (string/split ":" address))
  (def host (parts 0))
  (def port (if (= (length parts) 1) 22 (scan-number (parts 1))))
  (def result (exec-slurp "ssh-keyscan" "-p" (string port) host))
  (store/set (string "hosts/" host ":" port) result))

(defn import []
  (def hosts-path (path/join (home) ".ssh" "known_hosts"))
  (def old-lines (string/split (slurp hosts-path) "\n"))
  (def new-lines (mapcat |(string/split "\n" $0) (store/ls-contents "hosts/*")))
  (spit hosts-path (string/join (distinct (array/concat old-lines new-lines)) "\n"))) # TODO more intelligent algorithm that detects conflicts in differing keys and uses the ones from the store
