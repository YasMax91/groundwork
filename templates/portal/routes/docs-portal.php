<?php

use App\Http\Controllers\DocsPortalController;
use App\Http\Middleware\VerifyDocsPortalToken;
use Illuminate\Support\Facades\Route;

/*
 * Frontend documentation portal. Required from routes/web.php only when the portal is
 * enabled, so on production these routes are never registered — see config/docs_portal.php.
 */
Route::prefix('dev/docs/{token}')
    ->middleware(VerifyDocsPortalToken::class)
    ->name('docs-portal.')
    ->group(function () {
        Route::get('/', [DocsPortalController::class, 'index'])->name('index');
        Route::get('/index.json', [DocsPortalController::class, 'json'])->name('json');
        Route::get('/f/{feature}', [DocsPortalController::class, 'feature'])->name('feature');
        Route::get('/d/{slug}', [DocsPortalController::class, 'document'])->name('document');
        Route::get('/raw/{path}', [DocsPortalController::class, 'raw'])->where('path', '.*')->name('raw');
    });
