webpackJsonp([85],{661:function(e,c,t){"use strict";function o(e){var c=e.detail,t=c[0],o=document.querySelector('[data-id="'+t.id+'"]');o&&o.parentNode.removeChild(o)}Object.defineProperty(c,"__esModule",{value:!0});var n=t(152);t.n(n);[].forEach.call(document.querySelectorAll(".trash-button"),function(e){e.addEventListener("ajax:success",o)});var l='.batch-checkbox input[type="checkbox"]';Object(n.delegate)(document,"#batch_checkbox_all","change",function(e){var c=e.target;[].forEach.call(document.querySelectorAll(l),function(e){e.checked=c.checked})}),Object(n.delegate)(document,l,"change",function(){var e=document.querySelector("#batch_checkbox_all");e&&(e.checked=[].every.call(document.querySelectorAll(l),function(e){return e.checked}),e.indeterminate=!e.checked&&[].some.call(document.querySelectorAll(l),function(e){return e.checked}))}),Object(n.delegate)(document,".media-spoiler-show-button","click",function(){[].forEach.call(document.querySelectorAll("button.media-spoiler"),function(e){e.click()})}),Object(n.delegate)(document,".media-spoiler-hide-button","click",function(){[].forEach.call(document.querySelectorAll(".spoiler-button.spoiler-button--visible button"),function(e){e.click()})})}},[661]);
//# sourceMappingURL=admin.js.map