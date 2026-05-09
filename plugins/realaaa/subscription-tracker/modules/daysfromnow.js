/*\
title: $:/plugins/realaaa/subscription-tracker/modules/daysfromnow.js
type: application/javascript
module-type: filteroperator

Filter operator that returns the current time + N days as a TiddlyWiki
timestamp string. Used by the "+ New subscription" button to default
the renewal-date field of newly-created subscription tiddlers.

Usage: [daysfromnow[30]] → "YYYYMMDDhhmmssXXX" 17-digit TW timestamp
       30 days from now. Negative operands work too: [daysfromnow[-7]]
       returns 7 days ago.

Why a JS module: TW 5.4 core has no date-arithmetic filter operator
(no addmonths, adddays, addyears, or even a `now` filter). The
existing `nextrenewal.js` module covers a similar gap for renewal-date
auto-roll. Self-contained in this plugin — no external deps.

\*/
"use strict";

exports.daysfromnow = function(source, operator, options) {
    var days = parseInt(operator.operand, 10);
    if (!isFinite(days)) return [];
    var d = new Date();
    d.setDate(d.getDate() + days);
    return [$tw.utils.stringifyDate(d)];
};
