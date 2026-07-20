// Live coupon price preview for the Pro plan signup page.
//
// Listens on the coupon_code field, asks the server (plan_coupon_preview) what
// the discounted price would be, and updates the plan overview before the user
// submits. All server values are written via textContent - the discounted
// amount and the coupon terms both originate from Stripe and must never be
// treated as HTML.
(function () {
  'use strict';

  var wrap = document.querySelector('.plan-coupon[data-preview-url]');
  if (!wrap) { return; }

  var input = document.getElementById('coupon_code');
  var amountEl = document.getElementById('js-plan-amount');
  var priceEl = document.getElementById('js-plan-price');
  var originalEl = document.getElementById('js-plan-original');
  var savingEl = document.getElementById('js-plan-saving');
  var feedbackEl = document.getElementById('js-coupon-feedback');
  if (!input || !priceEl) { return; }

  var url = wrap.getAttribute('data-preview-url');
  var original = amountEl.getAttribute('data-original');
  var seq = 0;
  var timer;

  function reset() {
    priceEl.textContent = original;
    originalEl.hidden = true;
    originalEl.textContent = '';
    savingEl.hidden = true;
    savingEl.textContent = '';
  }

  function apply(mine, data) {
    if (mine !== seq) { return; } // a newer request has superseded this one

    if (data.status === 'valid') {
      priceEl.textContent = data.amount;
      originalEl.textContent = data.original;
      originalEl.hidden = false;
      if (data.saving) {
        savingEl.textContent = data.saving;
        savingEl.hidden = false;
      }
      feedbackEl.textContent = data.terms || '';
      feedbackEl.className = 'plan-coupon__feedback plan-coupon__feedback--valid';
    } else if (data.status === 'empty') {
      reset();
      feedbackEl.textContent = '';
      feedbackEl.className = 'plan-coupon__feedback';
    } else {
      // invalid / expired / error
      reset();
      feedbackEl.textContent = data.message || '';
      feedbackEl.className = 'plan-coupon__feedback plan-coupon__feedback--invalid';
    }
  }

  input.addEventListener('input', function () {
    clearTimeout(timer);
    timer = setTimeout(function () {
      var mine = ++seq;
      var code = input.value.trim();

      fetch(url + '?coupon_code=' + encodeURIComponent(code), {
        headers: { 'Accept': 'application/json' },
        credentials: 'same-origin'
      }).then(function (response) {
        return response.ok ? response.json() : Promise.reject();
      }).then(function (data) {
        apply(mine, data);
      }).catch(function () {
        // Non-JSON response (e.g. session expired -> login page) or network
        // error: fail quietly and leave the list price in place.
        if (mine === seq) {
          reset();
          feedbackEl.textContent = '';
          feedbackEl.className = 'plan-coupon__feedback';
        }
      });
    }, 350);
  });
})();
