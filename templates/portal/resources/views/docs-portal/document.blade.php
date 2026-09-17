@extends('docs-portal.layout', ['title' => $document['title']])

@section('content')
    <p class="crumb">
        <a href="{{ route('docs-portal.index', ['token' => $token]) }}">← всі розділи</a>
        @if ($feature)
            · <a href="{{ route('docs-portal.feature', ['token' => $token, 'feature' => $feature['slug']]) }}">{{ $feature['title'] }}</a>
        @endif
    </p>

    <h1>{{ $document['title'] }}</h1>
    <p class="lede">
        {{ $document['date'] }}
        @if ($document['breaking'])<span class="badge breaking">ламає контракт</span>@endif
        @if ($document['lang'] === 'ru')<span class="badge ru">російською</span>@endif
    </p>

    @if ($document['status'] === 'superseded')
        <p class="notice">
            Цю дельту перекрито пізнішою@if ($document['superseded_by']) — {{ $document['superseded_by'] }}@endif.
            Читайте її як історію, а не як чинний контракт.
        </p>
    @endif

    <div class="doc">{!! $document['html'] !!}</div>

    <div class="toolbar">
        <a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $document['path'], 'download' => 1]) }}">Завантажити .md</a>
        <a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $document['path']]) }}">Відкрити як текст</a>
    </div>

    @if ($document['http'] || $document['openapi'])
        <h2>Готові запити і контракт</h2>
        <ul class="files">
            @foreach ($document['http'] as $file)
                <li><a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $file, 'download' => 1]) }}">{{ basename($file) }}</a> — запити, які можна виконати</li>
            @endforeach
            @foreach ($document['openapi'] as $file)
                <li><a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $file, 'download' => 1]) }}">{{ basename($file) }}</a> — знімок OpenAPI, з нього генеруються типи</li>
            @endforeach
        </ul>
    @endif
@endsection
