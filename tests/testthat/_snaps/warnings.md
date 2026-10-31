# removed rows warnings match

    Code
      alot_conditions(p)
    Output
      [1] "warning: Orientation is not uniquely specified when both the x and y aesthetics are continuous. Picking default orientation 'x'."
      [2] "warning: Removed 1 row containing missing values or values outside the scale range (`stat_boxplot()`)."                          
      [3] "warning: Removed 1 row containing non-finite outside the scale range (`stat_boxplot()`)."                                        

---

    Code
      alot_conditions(p)
    Output
      [1] "warning: Removed 2 rows containing non-finite outside the scale range (`stat_bin()`)."

# stat_bin's default-bins message matches

    Code
      alot_conditions(p)
    Output
      [1] "message: `stat_bin()` using `bins = 30`. Pick better value `binwidth`."

# scale warnings match

    Code
      alot_conditions(p)
    Output
      [1] "warning: NaNs produced"                                  
      [2] "warning: sqrt transformation introduced infinite values."

---

    Code
      alot_conditions(p)
    Output
      [1] "warning: Removed 11 rows containing non-finite outside the scale range (`stat_smooth()`)."

