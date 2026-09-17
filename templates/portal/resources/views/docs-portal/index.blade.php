@extends('docs-portal.layout', ['title' => 'Документація бекенду для фронтенду'])

@section('content')
    @if ($master)
        <div class="doc">{!! $master['html'] !!}</div>
        <div class="toolbar">
            <a href="{{ route('docs-portal.raw', ['token' => $token, 'path' => $master['path'], 'download' => 1]) }}">Завантажити майстер-хендофф</a>
        </div>
    @else
        <h1>Документація бекенду для фронтенду</h1>
        <p class="lede">Майстер-хендофф ще не написано.</p>
    @endif

    @foreach ($areas as $area)
        <section class="area">
            <h2>{{ $area['title'] }}</h2>
            <div class="cards">
                @foreach ($area['features'] as $feature)
                    <a class="card" href="{{ route('docs-portal.feature', ['token' => $token, 'feature' => $feature['slug']]) }}">
                        <span class="name">{{ $feature['title'] }}</span>
                        <span class="sub">
                            дельт: {{ count($feature['handoffs']) }}
                            @if ($feature['updated']) · оновлено {{ $feature['updated'] }} @endif
                            @if ($feature['breaking'])<span class="badge breaking">ламає контракт: {{ $feature['breaking'] }}</span>@endif
                            @unless ($feature['doc'])<span class="badge gap">без зведеного документа</span>@endunless
                        </span>
                    </a>
                @endforeach
            </div>
        </section>
    @endforeach
@endsection
