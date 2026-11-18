// Keeps the deadline sentence in the Pro request advice honest.
//
// The advice is rendered once on the server for the authority chosen when the
// page loaded. The host's authority picker can change the authority without a
// reload, so when it does we fall back to the neutral wording rather than
// showing the previous authority's deadline. The text is written via
// textContent, never as HTML.
(function () {
  'use strict';

  var $ = window.jQuery;
  if (!$) { return; }

  $(function () {
    var advice = document.getElementById('js-advice-deadline');
    var neutral = advice && advice.getAttribute('data-neutral-text');
    if (!neutral) { return; }

    // Selectize raises 'change' through jQuery on the original input, which
    // native listeners do not see, so this has to be a jQuery handler.
    $('.js-authority-select').on('change', function () {
      advice.textContent = neutral;
    });
  });
})();
