// WYSIWYG Editor Scripts

document.addEventListener('DOMContentLoaded', function() {
	initWysiwygEditor();
});

function initWysiwygEditor() {
	window.formatText = formatText;
	window.insertLink = insertLink;
	window.updateHiddenTextarea = updateHiddenTextarea;

	var editor = document.getElementById('text_content_editor');
	if (editor) {
		setupPlaceholder();
		setupFormHandling();
		setupBlockquoteHandling();
	}

	injectEditorStyles();
	setupPostResponseHandlers();
}

function formatText(command) {
	var editor = document.getElementById('text_content_editor');
	if (!editor) return;

	editor.focus();

	if (command === 'blockquote') {
		var selection = window.getSelection();
		if (selection.rangeCount > 0) {
			var range = selection.getRangeAt(0);
			var selectedText = range.toString();

			var blockquote = document.createElement('blockquote');
			var quoteBody = document.createElement('p');
			quoteBody.textContent = selectedText || 'Quote text here';
			var cite = document.createElement('cite');
			cite.textContent = 'Attribution';
			cite.setAttribute('contenteditable', 'true');
			blockquote.appendChild(quoteBody);
			blockquote.appendChild(cite);

			range.deleteContents();
			range.insertNode(blockquote);

			var textNode = quoteBody.firstChild;
			if (textNode) {
				var newRange = document.createRange();
				newRange.selectNodeContents(textNode);
				selection.removeAllRanges();
				selection.addRange(newRange);
			}
		}
	} else {
		try {
			if (document.execCommand) {
				document.execCommand(command, false, null);
			} else {
				handleModernFormatting(command);
			}
		} catch (e) {
			console.warn('Formatting command failed:', command, e);
			handleModernFormatting(command);
		}
	}
	editor.focus();
}

function handleModernFormatting(command) {
	var selection = window.getSelection();
	if (selection.rangeCount === 0) return;

	var range = selection.getRangeAt(0);
	var selectedText = range.toString();

	if (!selectedText) return;

	var element;
	switch(command) {
		case 'bold':
			element = document.createElement('strong');
			break;
		case 'italic':
			element = document.createElement('em');
			break;
		case 'underline':
			element = document.createElement('u');
			break;
		default:
			return;
	}

	element.textContent = selectedText;
	range.deleteContents();
	range.insertNode(element);

	selection.removeAllRanges();
	var newRange = document.createRange();
	newRange.setStartAfter(element);
	newRange.collapse(true);
	selection.addRange(newRange);
}

function insertLink() {
	var editor = document.getElementById('text_content_editor');
	if (!editor) return;

	editor.focus();
	var url = prompt('Enter the link URL:');
	if (url) {
		var selection = window.getSelection();
		if (selection.rangeCount > 0) {
			var range = selection.getRangeAt(0);
			var selectedText = range.toString();

			var link = document.createElement('a');
			link.href = url;
			link.textContent = selectedText || url;

			range.deleteContents();
			range.insertNode(link);

			selection.removeAllRanges();
			var newRange = document.createRange();
			newRange.setStartAfter(link);
			newRange.collapse(true);
			selection.addRange(newRange);
		}
		editor.focus();
	}
}

function updateHiddenTextarea() {
	var editor = document.getElementById('text_content_editor');
	var hiddenTextarea = document.getElementById('text_content');
	if (editor && hiddenTextarea) {
		var clone = editor.cloneNode(true);
		clone.querySelectorAll('blockquote cite').forEach(function(cite) {
			if (cite.textContent === 'Attribution') cite.remove();
		});
		hiddenTextarea.value = clone.innerHTML;
	}
}

function setupPlaceholder() {
	var editor = document.getElementById('text_content_editor');
	if (!editor) return;

	editor.addEventListener('focus', function() {
		if (this.innerHTML === '') this.innerHTML = '';
	});

	editor.addEventListener('blur', function() {
		if (this.innerHTML === '') this.innerHTML = '';
	});
}

function injectEditorStyles() {
	var style = document.createElement('style');
	style.textContent =
		'#text_content_editor:empty:before,' +
		'[id^="edit-editor-"]:empty:before {' +
		'  content: attr(placeholder);' +
		'  color: var(--color-text-muted);' +
		'  font-style: italic;' +
		'  pointer-events: none;' +
		'}' +
		'#text_content_editor:focus:before,' +
		'[id^="edit-editor-"]:focus:before {' +
		'  content: "";' +
		'}' +
		'.toolbar-btn {' +
		'  background: var(--color-background) !important;' +
		'  border: 1px solid var(--color-border) !important;' +
		'  border-radius: 0.25rem !important;' +
		'  cursor: pointer !important;' +
		'  transition: all 0.2s !important;' +
		'  color: inherit !important;' +
		'  font-family: inherit !important;' +
		'  font-size: inherit !important;' +
		'}' +
		'.toolbar-btn:hover {' +
		'  background: var(--color-surface-variant) !important;' +
		'  transform: translateY(-1px);' +
		'}' +
		'.toolbar-btn:active {' +
		'  background: var(--color-border) !important;' +
		'  transform: translateY(0);' +
		'}' +
		'blockquote {' +
		'  border-left: 4px solid var(--color-border) !important;' +
		'  padding-left: 1rem !important;' +
		'  margin: 1rem 0 !important;' +
		'  color: var(--color-text-muted) !important;' +
		'  font-style: italic !important;' +
		'}' +
		'#text_content_editor blockquote p,' +
		'[id^="edit-editor-"] blockquote p {' +
		'  margin: 0 0 0.25rem 0 !important;' +
		'}' +
		'#text_content_editor blockquote cite,' +
		'[id^="edit-editor-"] blockquote cite {' +
		'  display: block !important;' +
		'  font-size: 0.85em !important;' +
		'  font-style: normal !important;' +
		'  color: var(--color-text-muted) !important;' +
		'  opacity: 0.8;' +
		'}' +
		'#text_content_editor blockquote cite::before,' +
		'[id^="edit-editor-"] blockquote cite::before {' +
		'  content: "\\2014  " !important;' +
		'}';
	document.head.appendChild(style);
}

function setupPostResponseHandlers() {
	document.addEventListener('htmx:afterSwap', function(event) {
		if (event.detail.target.id === 'post-response') {
			var responseDiv = event.detail.target;
			responseDiv.style.display = 'block';
			if (responseDiv.innerHTML.includes('successfully')) {
				var editor = document.getElementById('text_content_editor');
				var hiddenTextarea = document.getElementById('text_content');
				var imageInput = document.getElementById('image');

				if (editor) editor.innerHTML = '';
				if (hiddenTextarea) hiddenTextarea.value = '';
				if (imageInput) imageInput.value = '';

				setTimeout(function() {
					window.location.reload();
				}, 1000);
			} else {
				setTimeout(function() { responseDiv.style.display = 'none'; }, 5000);
			}
		}
	});

	document.addEventListener('htmx:responseError', function(event) {
		if (event.detail.target && event.detail.target.id === 'post-response') {
			event.preventDefault();
			var responseDiv = event.detail.target;
			var status = event.detail.xhr.status;
			var msg = 'An error occurred while creating your post.';
			if (status === 401) msg = 'You must be logged in to create posts.';
			else if (status === 409) msg = 'A conflict occurred. Please try again.';
			else if (status === 413) msg = 'The uploaded file is too large. Maximum size is 10MB.';
			else if (status === 415) msg = 'The uploaded file type is not supported. Please use JPG, PNG, GIF, or WebP.';
			else if (status >= 500) msg = 'A server error occurred. Please try again later.';
			responseDiv.innerHTML = '<p style="color: var(--error-oklch-500);">' + msg + '</p>';
			responseDiv.style.display = 'block';
			setTimeout(function() { responseDiv.style.display = 'none'; }, 5000);
		}
	});
}

function setupFormHandling() {
	var postForm = document.getElementById('post-form');
	if (postForm) {
		postForm.addEventListener('htmx:configRequest', function(event) {
			updateHiddenTextarea();
		});
	}
}

function setupBlockquoteHandling() {
	var editor = document.getElementById('text_content_editor');
	if (!editor) return;
	attachBlockquoteHandling(editor);
}

function attachBlockquoteHandling(editor) {
	var lastEnterTime = 0;
	var doubleEnterThreshold = 500;

	editor.addEventListener('keydown', function(event) {
		var selection = window.getSelection();
		var range = selection.rangeCount > 0 ? selection.getRangeAt(0) : null;
		if (!range) return;

		var currentNode = range.startContainer;
		var blockquote = null;
		var cite = null;

		while (currentNode && currentNode !== editor) {
			if (currentNode.nodeType === Node.ELEMENT_NODE) {
				if (currentNode.tagName === 'CITE') cite = currentNode;
				if (currentNode.tagName === 'BLOCKQUOTE') { blockquote = currentNode; break; }
			}
			currentNode = currentNode.parentNode;
		}

		if (!blockquote) { lastEnterTime = 0; return; }

		if (event.key === 'Tab') {
			event.preventDefault();
			var citeEl = blockquote.querySelector('cite');
			var bodyEl = blockquote.querySelector('p');
			if (cite && bodyEl) {
				selectNodeContents(bodyEl);
			} else if (citeEl) {
				selectNodeContents(citeEl);
			}
		} else if (event.key === 'Enter') {
			event.preventDefault();

			if (cite) {
				escapeBlockquote(blockquote);
			} else {
				var currentTime = Date.now();
				var isDoubleEnter = (currentTime - lastEnterTime) < doubleEnterThreshold;
				lastEnterTime = currentTime;

				if (isDoubleEnter) {
					var citeEl2 = blockquote.querySelector('cite');
					if (citeEl2) selectNodeContents(citeEl2);
				} else {
					var br = document.createElement('br');
					range.insertNode(br);
					var newRange = document.createRange();
					newRange.setStartAfter(br);
					newRange.collapse(true);
					selection.removeAllRanges();
					selection.addRange(newRange);
				}
			}
		} else {
			lastEnterTime = 0;
		}
	});
}

function selectNodeContents(node) {
	var sel = window.getSelection();
	var r = document.createRange();
	r.selectNodeContents(node);
	sel.removeAllRanges();
	sel.addRange(r);
}

function deletePost(postId) {
	if (!confirm('Delete this post?')) return;
	fetch('/delete-post', {
		method: 'POST',
		headers: {'Content-Type': 'application/x-www-form-urlencoded'},
		body: 'post_id=' + postId
	}).then(function(r) {
		if (r.redirected) {
			window.location.href = r.url;
		} else {
			window.location.reload();
		}
	});
}

function editPost(postId) {
	var card = document.getElementById('post-card-' + postId);
	if (!card) return;

	var textEl = card.querySelector('.post-text-content');
	var imageEl = card.querySelector('.post-image img');
	var currentText = textEl ? textEl.innerHTML : '';
	var currentImage = imageEl ? imageEl.getAttribute('src') : '';
	var hasImage = currentImage !== '';

	var linkSvg = '<svg width="1em" height="1em" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
		'<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>' +
		'<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>';

	var html =
		'<form id="edit-post-form-' + postId + '" enctype="multipart/form-data" style="margin: 0;">' +
		'<input type="hidden" name="post_id" value="' + postId + '">' +
		'<div id="edit-toolbar-' + postId + '" style="border: 1px solid var(--color-border); border-bottom: none; border-radius: 0.375rem 0.375rem 0 0; padding: 0.5rem; background: var(--color-background); display: flex; flex-wrap: wrap; gap: 0.25rem;">' +
		'<button type="button" onclick="editFormatText(' + postId + ', \'bold\')" title="Bold" class="toolbar-btn" style="padding: 0.25rem 0.5rem; font-weight: bold;">B</button>' +
		'<button type="button" onclick="editFormatText(' + postId + ', \'italic\')" title="Italic" class="toolbar-btn" style="padding: 0.25rem 0.5rem; font-style: italic;">I</button>' +
		'<button type="button" onclick="editFormatText(' + postId + ', \'underline\')" title="Underline" class="toolbar-btn" style="padding: 0.25rem 0.5rem; text-decoration: underline;">U</button>' +
		'<button type="button" onclick="editFormatText(' + postId + ', \'blockquote\')" title="Quote" class="toolbar-btn" style="padding: 0.25rem 0.5rem;">&ldquo;</button>' +
		'<button type="button" onclick="editInsertLink(' + postId + ')" title="Link" class="toolbar-btn" style="padding: 0.25rem 0.5rem;">' + linkSvg + '</button>' +
		'</div>' +
		'<div id="edit-editor-' + postId + '" contenteditable="true" placeholder="Post text here..." style="border: 1px solid var(--color-border); border-radius: 0 0 0.375rem 0.375rem; padding: 0.5rem; min-height: 100px; background: var(--color-background);">' + currentText + '</div>';

	if (hasImage) {
		html +=
			'<div style="margin: 0.5rem 0;">' +
			'<img src="' + currentImage + '" alt="Current image" style="max-width: 100%; height: auto; border-radius: 0.375rem; max-height: 200px;">' +
			'<label style="display: flex; align-items: center; gap: 0.5rem; margin-top: 0.5rem; cursor: pointer;">' +
			'<input type="checkbox" id="remove-image-' + postId + '" style="width: auto;"> Remove image' +
			'</label></div>';
	}

	html +=
		'<label style="margin-top: 0.5rem;">' +
		(hasImage ? 'Replace' : 'Add') + ' picture (optional)' +
		'<input type="file" id="edit-image-' + postId + '" accept="image/*">' +
		'</label>' +
		'<div style="display: flex; gap: 0.5rem; justify-content: flex-end; margin-top: 0.5rem;">' +
		'<button type="button" class="secondary outline" style="padding: 0.25rem 0.75rem; color: var(--neutral-oklch-50);" onclick="window.location.reload()">Cancel</button>' +
		'<button type="button" style="padding: 0.25rem 0.75rem;" onclick="submitEditPost(' + postId + ')">Save</button>' +
		'</div></form>';

	card.innerHTML = html;

	// Attach blockquote handling to the new edit editor
	var editEditor = document.getElementById('edit-editor-' + postId);
	if (editEditor) {
		attachBlockquoteHandling(editEditor);
	}
}

function editFormatText(postId, command) {
	var editor = document.getElementById('edit-editor-' + postId);
	if (!editor) return;
	editor.focus();

	if (command === 'blockquote') {
		var selection = window.getSelection();
		if (selection.rangeCount > 0) {
			var range = selection.getRangeAt(0);
			var selectedText = range.toString();

			var blockquote = document.createElement('blockquote');
			var quoteBody = document.createElement('p');
			quoteBody.textContent = selectedText || 'Quote text here';
			var cite = document.createElement('cite');
			cite.textContent = 'Attribution';
			cite.setAttribute('contenteditable', 'true');
			blockquote.appendChild(quoteBody);
			blockquote.appendChild(cite);

			range.deleteContents();
			range.insertNode(blockquote);

			var textNode = quoteBody.firstChild;
			if (textNode) {
				var newRange = document.createRange();
				newRange.selectNodeContents(textNode);
				selection.removeAllRanges();
				selection.addRange(newRange);
			}
		}
	} else {
		try {
			document.execCommand(command, false, null);
		} catch (e) {
			console.warn('Formatting command failed:', command, e);
		}
	}
	editor.focus();
}

function editInsertLink(postId) {
	var editor = document.getElementById('edit-editor-' + postId);
	if (!editor) return;
	editor.focus();

	var url = prompt('Enter the link URL:');
	if (url) {
		var selection = window.getSelection();
		if (selection.rangeCount > 0) {
			var range = selection.getRangeAt(0);
			var selectedText = range.toString();

			var link = document.createElement('a');
			link.href = url;
			link.textContent = selectedText || url;

			range.deleteContents();
			range.insertNode(link);

			selection.removeAllRanges();
			var newRange = document.createRange();
			newRange.setStartAfter(link);
			newRange.collapse(true);
			selection.addRange(newRange);
		}
		editor.focus();
	}
}

function submitEditPost(postId) {
	var editor = document.getElementById('edit-editor-' + postId);
	if (!editor) return;

	var formData = new FormData();
	formData.append('post_id', postId);
	formData.append('text_content', editor.innerHTML);

	var removeCheckbox = document.getElementById('remove-image-' + postId);
	if (removeCheckbox && removeCheckbox.checked) {
		formData.append('remove_image', '1');
	}

	var fileInput = document.getElementById('edit-image-' + postId);
	if (fileInput && fileInput.files.length > 0) {
		formData.append('image', fileInput.files[0]);
	}

	fetch('/edit-post', {
		method: 'POST',
		body: formData
	}).then(function(r) {
		if (r.redirected) {
			window.location.href = r.url;
		} else {
			window.location.reload();
		}
	});
}

function escapeBlockquote(blockquote) {
	var cite = blockquote.querySelector('cite');
	if (cite && cite.textContent === 'Attribution') {
		cite.remove();
	}

	var newP = document.createElement('p');
	newP.innerHTML = '<br>';

	if (blockquote.nextSibling) {
		blockquote.parentNode.insertBefore(newP, blockquote.nextSibling);
	} else {
		blockquote.parentNode.appendChild(newP);
	}

	var newRange = document.createRange();
	newRange.setStart(newP, 0);
	newRange.collapse(true);
	var selection = window.getSelection();
	selection.removeAllRanges();
	selection.addRange(newRange);
}
