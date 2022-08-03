(use ./util)
(use ./store)

(defn- render [value]
  (case (type value)
    :function  (eval value)
    :string    value
    :boolean   (string value)
    :array     (string/format "%j" value)
    :tuple     (string/format "%j" value)
    :table     (string/format "%j" value)
    :struct    (string/format "%j" value)
    :buffer    (string value)
    :symbol    (string value)
    :keyword   (string value)
    :cfunction (error "Can't render :cfunctions")
    :fiber     (error "Can'r render :fiber")))

(defn local/set [key value] (cache/set (string "vars/" key) value))
(defn global/set [key value] (store/set (string "vars/" key) value))
(defn local/rm [key] (local/set key nil))
(defn global/rm [key] (global/set key nil))
(defn local/ls [pattern] (cache/ls (string "vars/" pattern)))
(defn global/ls [pattern] (store/ls (string "vars/" pattern)))
(defn local/get [key] (render (cache/get (string "vars/" key))))
(defn global/get [key] (render (store/get (string "vars/" key))))
(defn local/ls-contents [pattern]
  (if pattern
    (cache/ls-contents (string "vars/" pattern))
    (cache/ls-contents "vars/*")))
(defn global/ls-contents [pattern]
  (if pattern
    (store/ls-contents (string "vars/" pattern))
    (store/ls-contents "vars/*")))

(defn trim-prefix [prefix str]
  (if (string/has-prefix? prefix str)
      (slice str (length prefix) -1)
      str))

(defn export
  "returns the universal vars formatted for shell consumption as string"
  [&opt pattern]
  (def parts @[])
  (def vars (merge (global/ls-contents pattern) (local/ls-contents pattern)))
  (eachk key vars
    (array/push parts (string "export " (trim-prefix "vars/" key) "=\"" (render (vars key)) "\"")))
  (def node-name (cache/get "node/name"))
  (if node-name
      (array/push parts (string "export NODE_NAME=\"" node-name "\""))
      (array/push parts "export NODE_NAME=unknown"))
  (string/join parts "\n"))
