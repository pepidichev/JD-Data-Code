version 19
clear all
set more off
cap log close
cd "/Users/petar.dichev/Desktop/JD_Thesis_New"
log using "output/thesis_results_final.log", replace text

insheet using "data/JD_delivery_data.csv", clear
save "data/delivery.dta", replace

insheet using "data/JD_order_data.csv", clear
save "data/orders.dta", replace

insheet using "data/JD_user_data.csv", clear
save "data/users.dta", replace

use "data/delivery.dta", clear
bysort order_id (arr_time): keep if _n == _N
duplicates report order_id
save "data/delivery_dedup.dta", replace

use "data/orders.dta", clear
merge m:1 order_id using "data/delivery_dedup.dta"
tab _merge
keep if _merge == 3
drop _merge
gen order_dt = clock(order_time, "YMDhms#")
gen arr_dt = clock(arr_time, "YMDhms#")
format order_dt arr_dt %tc
gen actual_days = (arr_dt - order_dt) / (1000*60*60*24)
drop order_date
gen order_date = date(substr(order_time, 1, 10), "YMD")
format order_date %td
destring promise, replace force
drop if promise == .
gen promise_gap = actual_days - promise
label variable promise_gap "Actual minus promised delivery days"
gen backup = (dc_ori != dc_des)
label variable backup "1 = backup fulfillment, 0 = local fulfillment"
label variable actual_days "Actual delivery time in days"
drop if actual_days < 0
drop if actual_days > 30
drop if final_unit_price <= 0
save "data/analysis_base.dta", replace

use "data/orders.dta", clear
keep sku_id order_date quantity
collapse (sum) daily_sales=quantity, by(sku_id order_date)
bysort sku_id: egen mean_sales = mean(daily_sales)
bysort sku_id: egen sd_sales = sd(daily_sales)
gen cv = sd_sales / mean_sales
replace cv = 0 if missing(cv)
bysort sku_id: keep if _n == 1
keep sku_id cv mean_sales sd_sales
save "data/sku_cv.dta", replace

use "data/analysis_base.dta", clear
merge m:1 sku_id using "data/sku_cv.dta"
keep if _merge == 3
drop _merge
save "data/analysis_base.dta", replace

use "data/analysis_base.dta", clear
merge m:1 user_id using "data/users.dta"
keep if _merge == 3
drop _merge
drop if city_level == -1
save "data/analysis_final.dta", replace

insheet using "data/JD_inventory_data.csv", clear
bysort sku_id date: gen n_warehouses = _N
bysort sku_id date: keep if _n == 1
keep sku_id date n_warehouses
gen order_date = date(date, "YMD")
format order_date %td
drop date
save "data/sku_daily_coverage_temp.dta", replace

use "data/analysis_final.dta", clear
capture confirm string variable order_date
if _rc == 0 {
    gen order_date2 = date(order_date, "YMD")
    format order_date2 %td
    drop order_date
    rename order_date2 order_date
}
merge m:1 sku_id order_date using "data/sku_daily_coverage_temp.dta"
keep if _merge == 3
drop _merge
gen low_coverage = (n_warehouses < 35)
label variable n_warehouses "Number of warehouses stocking SKU on order date"
label variable low_coverage "1 = below median warehouse coverage"
save "data/sku_daily_coverage.dta", replace

use "data/analysis_final.dta", clear
summarize promise_gap actual_days backup type cv plus final_unit_price city_level mean_sales, separator(0)
tab type
tab backup
tab type backup, row

use "data/analysis_final.dta", clear
areg promise_gap type backup cv plus final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_stage1.doc", replace label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) title("Table 5.1: Stage 1 — Effect of Fulfillment Type on Promise Gap")

use "data/analysis_final.dta", clear
xi: logit backup type cv mean_sales final_unit_price city_level i.order_date, cluster(sku_id) nolog
margins, dydx(type cv mean_sales final_unit_price city_level)
outreg2 using "output/table_stage2.doc", replace label dec(3) stats(coef se pval) title("Table 5.2: Stage 2 — Predictors of Backup Fulfillment (Average Marginal Effects)")

use "data/analysis_final.dta", clear
gen backup_cv = backup * cv
gen backup_plus = backup * plus
label variable backup_cv "Backup x CV interaction"
label variable backup_plus "Backup x PLUS interaction"
areg promise_gap type backup cv plus backup_cv backup_plus final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_stage3.doc", replace label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) title("Table 5.3: Stage 3 — Heterogeneity of Promise Compensation")

use "data/sku_daily_coverage.dta", clear
xi: logit backup low_coverage cv mean_sales city_level i.order_date, cluster(sku_id) nolog
margins, dydx(low_coverage cv mean_sales city_level)
outreg2 using "output/table_stage4.doc", replace label dec(3) stats(coef se pval) title("Table 5.4: Stage 4 — Inventory Coverage as Operational Mechanism (Average Marginal Effects)")

use "data/analysis_final.dta", clear
areg actual_days type backup cv plus final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_robustness.doc", replace label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) ctitle("RC1: Actual Days") title("Table 5.5: Robustness Checks")

use "data/analysis_final.dta", clear
keep if type == 1
areg promise_gap backup cv plus final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_robustness.doc", append label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) ctitle("RC2: 1P Only")

use "data/analysis_final.dta", clear
areg backup type cv mean_sales final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_robustness.doc", append label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) ctitle("RC3: LPM")

use "data/analysis_final.dta", clear
keep if promise == 1
areg promise_gap type backup cv plus final_unit_price city_level, absorb(order_date) cluster(sku_id)
outreg2 using "output/table_robustness.doc", append label dec(3) stats(coef se pval) addstat("R-squared", e(r2), "Observations", e(N)) ctitle("RC4: 1-Day Promise")

use "data/analysis_final.dta", clear
estpost summarize promise_gap actual_days backup type cv plus final_unit_price city_level mean_sales
esttab using "output/table_descriptives.doc", replace cells("mean(fmt(3)) sd(fmt(3)) min(fmt(2)) max(fmt(2)) count(fmt(0))") title("Table 3: Descriptive Statistics") label noobs

log close
