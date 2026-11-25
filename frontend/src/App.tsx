// Routes of the SPA.
import { Navigate, Route, Routes } from 'react-router-dom';
import { Layout } from './components/Layout';
import { AboutPage } from './pages/AboutPage';
import { ExerciseDetailPage } from './pages/ExerciseDetailPage';
import { ExerciseListPage } from './pages/ExerciseListPage';
import { FamiliesPage } from './pages/FamiliesPage';
import { NotFoundPage } from './pages/NotFoundPage';

export function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Navigate to="/exercises" replace />} />
        <Route path="/exercises" element={<ExerciseListPage />} />
        <Route path="/exercises/:id" element={<ExerciseDetailPage />} />
        <Route path="/families" element={<FamiliesPage />} />
        <Route path="/about" element={<AboutPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
