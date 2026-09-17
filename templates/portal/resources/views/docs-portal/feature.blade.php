@extends('docs-portal.layout', ['title' => $feature['title']])

@section('content')
    <p class="crumb"><a href="{{ route('docs-portal.index', ['token' => $token]) }}">← всі розділи</a></p>
    <h1>{{ $feature['title'] }}</h1>
    <p class="lede">
        дельт: {{ count($feature['handoffs']) }}
        @if ($feature['updated']) · останні зміни {{ $feature['updated'] }} @endif
    </p>

    @if ($feature['doc'])
        <div class="doc">{!! $feature['doc']['html'] !!}</div>
        <div class="toolbar">
            <a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $feature['doc']['path'], 'download' => 1]) }}">Завантажити .md</a>
            <a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $feature['doc']['path']]) }}">Відкрити як текст</a>
        </div>
    @else
        <p class="notice">Зведеного документа по цій фічі ще немає — нижче тільки дельти, у порядку від нової до старої.</p>
    @endif

    @foreach ($feature['extra'] as $extra)
        <h2>{{ $extra['title'] }}</h2>
        <div class="doc">{!! $extra['html'] !!}</div>
    @endforeach

    <h2>Історія змін</h2>
    <ol class="deltas">
        @foreach ($feature['handoffs'] as $handoff)
            <li>
                <span class="date">{{ $handoff['date'] }}</span>
                <a href="{{ route('docs-portal.document', ['token' => $token, 'slug' => $handoff['slug']]) }}">{{ $handoff['title'] }}</a>
                @if ($handoff['breaking'])<span class="badge breaking">ламає контракт</span>@endif
                @if ($handoff['status'] === 'superseded')<span class="badge stale">перекрито</span>@endif
                @if ($handoff['lang'] === 'ru')<span class="badge ru">рос.</span>@endif
            </li>
        @endforeach
    </ol>

    @if ($feature['mentions'])
        <h2>Зачіпали цю фічу</h2>
        <ol class="deltas">
            @foreach ($feature['mentions'] as $mention)
                <li>
                    <span class="date">{{ $mention['date'] }}</span>
                    <a href="{{ route('docs-portal.document', ['token' => $token, 'slug' => $mention['slug']]) }}">{{ $mention['title'] }}</a>
                    @if ($mention['breaking'])<span class="badge breaking">ламає контракт</span>@endif
                </li>
            @endforeach
        </ol>
    @endif
@endsection
