// ==UserScript==
// @name         PR to Neovim DiffView
// @namespace    http://tampermonkey.net/
// @version      1.0.0
// @description  GitHubとGitBucketのPRページにNeovim DiffViewを開くボタンを追加する
// @match        https://github.com/*/pull/*
// @match        http://192.168.208.80:8080/gitbucket/*/pull/*
// @grant        GM_xmlhttpRequest
// @connect      localhost
// ==/UserScript==

(function () {
  'use strict';

  const SERVER_URL = 'http://localhost:8765';

  // --------------------------------------------------------------------------
  // URL解析
  // --------------------------------------------------------------------------

  function parseGitHub() {
    // https://github.com/{owner}/{repo}/pull/{number}
    const m = location.pathname.match(/^\/([^/]+)\/([^/]+)\/pull\/(\d+)/);
    if (!m) return null;
    const [, owner, repo, pr_number] = m;

    // head_ref: data-head-ref属性 or .head-ref要素
    let head_ref = null;
    const headRefEl = document.querySelector('[data-head-ref]');
    if (headRefEl) {
      head_ref = headRefEl.getAttribute('data-head-ref');
    } else {
      const spanEl = document.querySelector('.head-ref');
      if (spanEl) head_ref = spanEl.textContent.trim();
    }

    return { host: 'github', owner, repo, pr_number: parseInt(pr_number), head_ref };
  }

  function parseGitBucket() {
    // http://192.168.208.80:8080/gitbucket/{owner}/{repo}/pull/{number}
    const m = location.pathname.match(/^\/gitbucket\/([^/]+)\/([^/]+)\/pull\/(\d+)/);
    if (!m) return null;
    const [, owner, repo, pr_number] = m;

    // head_ref: GitBucketのPRページのブランチ表示から取得
    let head_ref = null;
    // "from {branch}" のようなテキストを探す
    const branchLink = document.querySelector('.pull-request-branch-from a, .compare-ref a');
    if (branchLink) {
      head_ref = branchLink.textContent.trim();
    }

    return { host: 'gitbucket', owner, repo, pr_number: parseInt(pr_number), head_ref };
  }

  function parsePRInfo() {
    if (location.hostname === 'github.com') return parseGitHub();
    if (location.hostname === '192.168.208.80') return parseGitBucket();
    return null;
  }

  // --------------------------------------------------------------------------
  // ボタン作成
  // --------------------------------------------------------------------------

  function createButton() {
    const btn = document.createElement('button');
    btn.textContent = 'Open in Neovim';
    btn.style.cssText = [
      'display: inline-flex',
      'align-items: center',
      'gap: 4px',
      'padding: 5px 12px',
      'font-size: 12px',
      'font-weight: 600',
      'line-height: 20px',
      'cursor: pointer',
      'border: 1px solid rgba(27,31,36,0.15)',
      'border-radius: 6px',
      'background-color: #f6f8fa',
      'color: #24292f',
      'margin-left: 8px',
      'white-space: nowrap',
    ].join(';');

    btn.addEventListener('mouseenter', () => {
      btn.style.backgroundColor = '#eaeef2';
    });
    btn.addEventListener('mouseleave', () => {
      btn.style.backgroundColor = '#f6f8fa';
    });

    return btn;
  }

  // --------------------------------------------------------------------------
  // ボタン挿入
  // --------------------------------------------------------------------------

  function insertButton(prInfo) {
    const btn = createButton();

    btn.addEventListener('click', () => {
      btn.textContent = 'Opening...';
      btn.disabled = true;

      GM_xmlhttpRequest({
        method: 'POST',
        url: `${SERVER_URL}/open-diffview`,
        headers: { 'Content-Type': 'application/json' },
        data: JSON.stringify(prInfo),
        onload(resp) {
          if (resp.status === 200) {
            btn.textContent = 'Opened!';
            setTimeout(() => {
              btn.textContent = 'Open in Neovim';
              btn.disabled = false;
            }, 2000);
          } else {
            btn.textContent = 'Error';
            btn.disabled = false;
            console.error('[PR DiffView]', resp.status, resp.responseText);
            alert(`エラー: ${resp.status}\n${resp.responseText}`);
          }
        },
        onerror(err) {
          btn.textContent = 'Error';
          btn.disabled = false;
          console.error('[PR DiffView] connection error', err);
          alert('サーバーに接続できません。pr-diffviewサーバーが起動しているか確認してください。');
        },
      });
    });

    // GitHub (新UI): prc-PageHeader-Actions
    const ghActionsNew = document.querySelector('[class*="prc-PageHeader-Actions"]');
    if (ghActionsNew) {
      ghActionsNew.prepend(btn);
      return true;
    }

    // GitHub (旧UI): .gh-header-actions
    const ghActions = document.querySelector('.gh-header-actions');
    if (ghActions) {
      ghActions.prepend(btn);
      return true;
    }

    // GitBucket: .pull-request-info や .issue-header-actions
    const gbActions = document.querySelector('.pull-request-info .btn-group, .issue-header .pull-right, .issue-header-actions');
    if (gbActions) {
      gbActions.appendChild(btn);
      return true;
    }

    // フォールバック: PR番号の近くのh1か最初のボタングループ
    const h1 = document.querySelector('h1.gh-header-title, h1.page-title');
    if (h1 && h1.parentElement) {
      h1.parentElement.appendChild(btn);
      return true;
    }

    console.warn('[PR DiffView] ボタン挿入位置が見つかりません。DOMを確認してください。');
    return false;
  }

  // --------------------------------------------------------------------------
  // 初期化
  // --------------------------------------------------------------------------

  function init() {
    const prInfo = parsePRInfo();
    if (!prInfo) return;

    // DOMが完全に読み込まれるまで少し待つ
    const tryInsert = (retries = 10) => {
      if (insertButton(prInfo)) return;
      if (retries > 0) setTimeout(() => tryInsert(retries - 1), 500);
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => tryInsert());
    } else {
      tryInsert();
    }
  }

  init();
})();
