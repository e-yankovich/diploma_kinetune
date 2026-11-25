// /about — what the prototype shows.
export function AboutPage() {
  return (
    <article className="prose">
      <h1>About Kinetune</h1>
      <p>
        Kinetune helps a coach of group stretching classes adapt a training plan to the group's
        condition. This prototype shows the exercise library: about 100 exercises, their joints with
        load levels, the stretched muscles and the two exercise graphs.
      </p>
      <ul>
        <li>
          <strong>Variations</strong> — exercises of the same family: another execution of the same
          movement, at any level.
        </li>
        <li>
          <strong>Regressions and progressions</strong> — one step easier or harder, derived from
          difficulty, mode, balance and joint load.
        </li>
      </ul>
      <p className="muted">
        Prototype version 0.1.0. Plans, sessions and recommendations come next.
      </p>
    </article>
  );
}
