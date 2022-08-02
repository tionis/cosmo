(use ./util)
(use ./store)

(defn local/set [key value] (cache/set (string "vars/" key) value))
(defn global/set [key value] (store/set (string "vars/" key) value))
(defn local/rm [key] (local/set key nil))
(defn global/rm [key] (global/set key nil))
(defn local/ls [pattern] (cache/ls (string "vars/" pattern)))
(defn global/ls [pattern] (store/ls (string "vars/" pattern)))
(defn local/get [key] (cache/get (string "vars/" key)))
(defn global/get [key] (store/get (string "vars/" key)))
(defn local/ls-contents [pattern]
  (if pattern
    (cache/ls-contents (string "vars/" pattern))
    (cache/ls-contents "vars/*")))
(defn global/ls-contents [pattern]
  (if pattern
    (store/ls-contents (string "vars/" pattern))
    (store/ls-contents "vars/*")))

(defn export
  "returns the universal vars formatted for shell consumption as string"
  [&opt pattern]
  (def parts @[])
  (def vars (merge (global/ls-contents pattern) (local/ls-contents pattern)))
  (eachk key vars (array/push parts (string "export " key "=\"" (vars key) "\"")))
  (def node-name (cache/get "node/name"))
  (if node-name
      (array/push parts (string "export NODE_NAME=\"" node-name "\""))
      (array/push parts "export NODE_NAME=unknown"))
  (string/join parts "\n"))
