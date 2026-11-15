namespace CanteenApi.Tests.Infrastructure;

/// <summary>
/// Đồng hồ giả cho test: đặt được thời điểm bất kỳ (kể cả lùi lại khi reset giữa các test),
/// khác với FakeTimeProvider chỉ cho phép tiến về phía trước.
/// </summary>
public sealed class TestClock(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Set(DateTimeOffset value) => _now = value;

    public void Advance(TimeSpan delta) => _now += delta;
}
