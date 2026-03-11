// Copy Code — injects a Copy button into each code block header bar.

(function() {
  const copyIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg>';
  const checkIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path></svg>';

  document.querySelectorAll('pre.mud-code').forEach(function(pre) {
    var header = pre.querySelector('.code-header');
    if (!header) {
      header = document.createElement('div');
      header.className = 'code-header';
      pre.insertBefore(header, pre.firstChild);
    }

    var btn = document.createElement('button');
    btn.className = 'code-copy-btn';
    btn.innerHTML = copyIcon + ' Copy';
    btn.addEventListener('click', function() {
      var code = pre.querySelector('code');
      if (!code) return;
      var text = code.textContent;
      navigator.clipboard.writeText(text).then(function() {
        btn.classList.add('copied');
        btn.innerHTML = checkIcon + ' Copied!';
        setTimeout(function() {
          btn.classList.remove('copied');
          btn.innerHTML = copyIcon + ' Copy';
        }, 2000);
      }, function() {
        // Fallback for contexts where clipboard API is unavailable.
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
        btn.classList.add('copied');
        btn.innerHTML = checkIcon + ' Copied!';
        setTimeout(function() {
          btn.classList.remove('copied');
          btn.innerHTML = copyIcon + ' Copy';
        }, 2000);
      });
    });
    header.appendChild(btn);
  });
})();
