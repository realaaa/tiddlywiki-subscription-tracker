/*\
title: $:/plugins/realaaa/subscription-tracker/modules/nextrenewal.js
type: application/javascript
module-type: filteroperator

Filter operator: takes an input date string and a period (in days) as operand.
Returns the next future occurrence of the date — i.e. if the input is already
in the future, returns it unchanged; if it's in the past, adds period-day
chunks until the result is in the future.

Used by sub.next-renewal to compute auto-rolled renewal dates without
requiring the user to manually update the field.

Why a JS module: TW 5.4 vanilla has no filter operator that adds N days
to a date string. The `days` operator selects tiddlers by date, not date
arithmetic. Self-contained in this plugin — no external deps.

\*/
"use strict";

exports.nextrenewal = function(source, operator, options) {
    var results = [];
    var now = new Date();
    var msPerDay = 24 * 60 * 60 * 1000;
    var periodDays = parseFloat(operator.operand);
    if (!isFinite(periodDays) || periodDays <= 0) {
        return results;
    }
    source(function(tiddler, title) {
        var d = $tw.utils.parseDate(title);
        if (!d || !$tw.utils.isDate(d) || d.toString() === "Invalid Date") return;
        if (d.getTime() >= now.getTime()) {
            results.push(title);
            return;
        }
        var daysSince = (now.getTime() - d.getTime()) / msPerDay;
        var periodsToAdd = Math.ceil(daysSince / periodDays);
        var newDate = new Date(d.getTime() + periodsToAdd * periodDays * msPerDay);
        results.push($tw.utils.stringifyDate(newDate));
    });
    return results;
};
